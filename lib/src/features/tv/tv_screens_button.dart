/// « Écrans » button of the map (lot 11, card validated on 30 Oct 2026,
/// 16 h 30, inspired by AirPlay screen mirroring): as soon as this device
/// has paired at least one screen (PCO and administrators: any screen of
/// the event), a button next to the right column sends the current view in
/// one gesture.
/// 1) one screen: a tap sends the view at once, « Vue envoyée à `nom` »;
/// 2) several screens: a short list by name with the connected state, a
///    tap sends the view; « Tous les écrans »;
/// 3) settings of each screen from the list (messages column, SOS banner,
///    disconnect);
/// 4) shown only when a screen is allowed, blue while a view is followed;
/// 5) « Suivre ma vue »: the screen follows the map until stopped;
/// 6) Outils › Écran Smart TV stays for pairing and full management.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show myActorId;
import '../../services/sarcade_api.dart';
import '../../ui/theme.dart' show themeMode;
import 'tv_view.dart';

/// A screen is « connected » when the TV asked for its state less than
/// 90 s ago (it asks every few seconds).
const tvConnectedWindow=Duration(seconds:90);

bool tvScreenConnected(Map<String,dynamic> d,DateTime now){
  final seen=d['last_seen'];
  if(seen is! num)return false;
  return now.millisecondsSinceEpoch/1000-seen<=tvConnectedWindow.inSeconds;
}

/// Screens behind the button: active, paired by me (`mine`), or any active
/// screen of the event for the PCO; ordered by name.
List<Map<String,dynamic>> tvButtonScreens(List<Map<String,dynamic>> all,{required bool pco}){
  final out=[for(final d in all)if(d['active']==true&&(pco||d['mine']==true))d];
  out.sort((a,b)=>'${a['name']??a['code']??''}'.toLowerCase().compareTo('${b['name']??b['code']??''}'.toLowerCase()));
  return out;
}

String tvScreenName(Map<String,dynamic> d){
  final n='${d['name']??''}'.trim();
  return n.isNotEmpty?n:'${d['code']??''}';
}

/// While a view is followed, a move of the map is sent at most every 2 s,
/// 600 ms after the last move.
const tvFollowDelay=Duration(milliseconds:600);
const tvFollowMinGap=Duration(seconds:2);

/// When to send the next followed view, [now] being the time of the move.
Duration tvFollowWait(DateTime now,DateTime? lastSent){
  if(lastSent==null)return tvFollowDelay;
  final gap=tvFollowMinGap-now.difference(lastSent);
  return gap>tvFollowDelay?gap:tvFollowDelay;
}

class TvScreensController extends ChangeNotifier {
  final SarcadeApi api; final String eventId;
  TvScreensController({required this.api,required this.eventId});

  List<Map<String,dynamic>> _all=const [];
  bool _pco=false;
  /// Screens following my view (ids).
  final Set<String> following={};
  DateTime? _lastSent; Timer? _pending; bool _disposed=false;

  List<Map<String,dynamic>> get screens=>tvButtonScreens(_all,pco:_pco);
  bool get visible=>screens.isNotEmpty;
  bool get isFollowing=>following.isNotEmpty;

  Future<void> refresh({required bool pco}) async {
    _pco=pco;
    try{
      _all=await api.displays(eventId);
      // A revoked or expired screen stops following.
      following.removeWhere((id)=>!screens.any((d)=>d['id']==id));
      if(!_disposed)notifyListeners();
    }catch(_){
      // Offline: the button keeps the last known screens.
    }
  }

  Map<String,dynamic>? _view(){
    final v=currentMapView?.call();
    if(v==null)return null;
    final o=currentMapOptions?.call();
    return tvViewJson(v,options:o,from:myActorId,theme:themeMode.value);
  }

  /// Sends the current view to [ids]; the key of the message to show.
  Future<String> send(List<String> ids,{bool live=false}) async {
    final json=_view();
    if(json==null)return 'tv.noMap';
    try{
      for(final id in ids){await api.sendDisplayView(eventId,id,json,live:live);}
      _lastSent=DateTime.now();
      return 'ok';
    }on SarcadeHttpException catch(e){
      return e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline';
    }catch(_){
      return 'event.offline';
    }
  }

  Future<String> follow(List<String> ids) async {
    following.addAll(ids);
    notifyListeners();
    return send(ids,live:true);
  }

  /// Stops following; the screens keep the last view sent.
  void stop([List<String>? ids]){
    if(ids==null){following.clear();}else{following.removeAll(ids);}
    if(following.isEmpty){_pending?.cancel();_pending=null;}
    notifyListeners();
  }

  /// Called on every move of the map.
  void mapMoved(){
    if(following.isEmpty)return;
    _pending?.cancel();
    _pending=Timer(tvFollowWait(DateTime.now(),_lastSent),(){
      _pending=null;
      if(!_disposed&&following.isNotEmpty)unawaited(send(following.toList(),live:true));
    });
  }

  @override void dispose(){_disposed=true;_pending?.cancel();super.dispose();}
}

/// The button itself, built with the floating button of the map ([fab]).
class TvScreensButton extends StatelessWidget {
  final TvScreensController controller;
  final Widget Function(String tooltip,Widget icon,VoidCallback onPressed,bool active) fab;
  /// Outils › Écran Smart TV (pairing and full management).
  final VoidCallback onManage;
  const TvScreensButton({super.key,required this.controller,required this.fab,required this.onManage});

  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:controller,builder:(context,_){
    if(!controller.visible)return const SizedBox.shrink();
    return GestureDetector(key:const ValueKey('map-screens'),
      onLongPress:()=>_openList(context),onSecondaryTap:()=>_openList(context),
      child:fab(S.t('tvb.title'),const Icon(Icons.screen_share_outlined),()=>_tap(context),controller.isFollowing));
  });

  Future<void> _tap(BuildContext context) async {
    final s=controller.screens;
    if(s.length==1&&!controller.isFollowing){
      await _send(context,[s.single]);
    }else{
      await _openList(context);
    }
  }

  Future<void> _send(BuildContext context,List<Map<String,dynamic>> to) async {
    final r=await controller.send([for(final d in to)'${d['id']}']);
    if(!context.mounted)return;
    final text=r!='ok'?S.t(r):to.length==1?S.t('tvb.sent',{'name':tvScreenName(to.single)}):S.t('tvb.sentAll',{'n':to.length});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
  }

  Future<void> _openList(BuildContext context)=>showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,
    builder:(c)=>TvScreensSheet(controller:controller,onSend:(to)async{Navigator.pop(c);await _send(context,to);},
      onManage:(){Navigator.pop(c);onManage();}));
}

/// List of the screens: tap = send the view; « Suivre ma vue »; settings.
class TvScreensSheet extends StatelessWidget {
  final TvScreensController controller;
  final Future<void> Function(List<Map<String,dynamic>> to) onSend;
  final VoidCallback onManage;
  const TvScreensSheet({super.key,required this.controller,required this.onSend,required this.onManage});

  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:controller,builder:(context,_){
    final t=Theme.of(context); final s=controller.screens; final now=DateTime.now();
    final allIds=[for(final d in s)'${d['id']}'];
    final allFollow=allIds.isNotEmpty&&allIds.every(controller.following.contains);
    return SafeArea(child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(context).height*.6),
      child:ListView(shrinkWrap:true,padding:const EdgeInsets.only(bottom:8),children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('tvb.title'),style:t.textTheme.titleMedium)),
        for(final d in s)_tile(context,d,now),
        if(s.length>1)ListTile(key:const ValueKey('tvb-all'),leading:const Icon(Icons.connected_tv),title:Text(S.t('tvb.all')),
          onTap:()=>onSend(s),
          trailing:_followButton(context,allIds,allFollow)),
        const Divider(),
        ListTile(leading:const Icon(Icons.settings_outlined),title:Text(S.t('tvb.manage')),onTap:onManage),
      ])));
  });

  Widget _followButton(BuildContext context,List<String> ids,bool on)=>TextButton.icon(
    onPressed:() async {
      if(on){controller.stop(ids);return;}
      final r=await controller.follow(ids);
      if(r!='ok'&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(r))));
    },
    icon:Icon(on?Icons.stop_circle_outlined:Icons.sync),label:Text(S.t(on?'tvb.followStop':'tvb.follow')));

  Widget _tile(BuildContext context,Map<String,dynamic> d,DateTime now){
    final id='${d['id']}'; final on=controller.following.contains(id); final connected=tvScreenConnected(d,now);
    final scheme=Theme.of(context).colorScheme;
    return ListTile(key:ValueKey('tvb-$id'),
      leading:Icon(d['alert']==true?Icons.sos:Icons.tv,color:d['alert']==true?scheme.error:connected?Colors.green:scheme.outline),
      title:Text(tvScreenName(d)),
      subtitle:Text([S.t(connected?'tvb.connected':'tvb.notConnected'),if(on)S.t('tvb.following')].join(' · ')),
      onTap:()=>onSend([d]),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        _followButton(context,[id],on),
        PopupMenuButton<String>(tooltip:S.t('tvb.settings'),onSelected:(a)=>_act(context,d,a),itemBuilder:(_)=>[
          PopupMenuItem(value:'messages',child:Text(S.t(d['messages']==false?'tv.messagesShow':'tv.messagesHide'))),
          if(d['alert']==true&&d['can_clear_alert']==true)PopupMenuItem(value:'sos',child:Text(S.t('tv.clearSos'))),
          PopupMenuItem(value:'revoke',child:Text(S.t('tvb.disconnect'))),
        ]),
      ]));
  }

  Future<void> _act(BuildContext context,Map<String,dynamic> d,String action) async {
    final api=controller.api, ev=controller.eventId, id='${d['id']}';
    String key;
    try{
      switch(action){
        case 'messages':
          final show=d['messages']==false;
          await api.setDisplayMessages(ev,id,show);key=show?'tv.messagesShown':'tv.messagesHidden';
        case 'sos':
          await api.clearDisplayAlert(ev,id);key='tv.sosCleared';
        default:
          controller.stop([id]);
          await api.revokeDisplay(ev,id);key='tvb.disconnected';
      }
    }on SarcadeHttpException catch(e){
      key=e.statusCode==403&&action=='sos'?'tv.sosForbidden':e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline';
    }catch(_){
      key='event.offline';
    }
    await controller.refresh(pco:controller._pco);
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(key))));
  }
}
