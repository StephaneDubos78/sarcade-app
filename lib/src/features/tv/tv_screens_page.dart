import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import '../../services/sarcade_api.dart';
import '../../ui/theme.dart' show themeMode;
import 'tv_code.dart';
import 'tv_nearby.dart';
import 'tv_qr_scan_page.dart';
import 'tv_view.dart';
import '../../ui/link_status.dart';

/// « Afficher sur une TV » (any operator, decision of the porteur of
/// 29 October 2026): pair the screen opened on tv.sarcade.org by scanning
/// its QR code (Android, iPhone) or typing its code, then list and revoke
/// the screens of the event.
class TvScreensPage extends StatelessWidget {
  final SarcadeApi api; final String eventId;
  /// The camera opens at once.
  final bool scanOnOpen;
  const TvScreensPage({super.key,required this.api,required this.eventId,this.scanOnOpen=false});
  @override Widget build(BuildContext context)=>Scaffold(appBar:LinkedAppBar(title:Text(S.t('tv.menu'))),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Text(S.t('tv.help'),style:Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height:16),
      TvScreensPanel(api:api,eventId:eventId,scanOnOpen:scanOnOpen),
    ]));
}

/// The content of « Afficher sur une TV » (the only place where the screens
/// are managed since 30 Oct 2026: section removed from Paramètres).
class TvScreensPanel extends StatefulWidget {
  final SarcadeApi api; final String eventId; final bool scanOnOpen;
  const TvScreensPanel({super.key,required this.api,required this.eventId,this.scanOnOpen=false});
  @override State<TvScreensPanel> createState()=>_TvScreensPanelState();
}

class _TvScreensPanelState extends State<TvScreensPanel> {
  List<Map<String,dynamic>>? _list; bool _busy=false; bool _offline=false;

  @override void initState(){
    super.initState();_load();
    if(widget.scanOnOpen&&canScanTvQr)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_scan();});
  }

  Future<void> _load() async {
    try{
      final l=await widget.api.displays(widget.eventId);
      if(mounted)setState((){_list=l;_offline=false;});
    }catch(_){
      if(mounted)setState(()=>_offline=true);
    }
  }

  void _say(String key){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(key))));
  }

  Future<void> _approve(String code,{String? name}) async {
    TvNearbyGate.handled(code);
    setState(()=>_busy=true);
    try{
      await widget.api.approveDisplay(code,widget.eventId,name:name);
      _say('tv.done');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'tv.unknownCode');
    }catch(_){
      _say('event.offline');
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  // Lot 11: the whole pairing (camera, name) suspends « Écran à proximité »;
  // a scanned code is never offered again by that dialog.
  Future<void> _scan()=>TvNearbyGate.during(() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const TvQrScanPage()));
    if(code==null||!mounted)return;
    TvNearbyGate.handled(code);
    // Name chosen at pairing, the default name of the TV proposed.
    final name=await _askName(S.t('tv.nameTitle'),await widget.api.tvCodeName(code)??'');
    if(name!=null&&mounted)await _approve(code,name:name);
  });

  /// Name of a screen (after the scan, « Renommer »); null when cancelled.
  Future<String?> _askName(String title,String initial) async {
    if(!mounted)return null;
    final ctrl=TextEditingController(text:initial);
    final v=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:Text(title),
      content:TextField(key:const ValueKey('tv-name'),controller:ctrl,autofocus:true,inputFormatters:[LengthLimitingTextInputFormatter(60)],
        decoration:InputDecoration(labelText:S.t('tv.name'),helperText:S.t('tv.nameHelp'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text.trim()),child:Text(S.t('common.ok')))]));
    ctrl.dispose();
    return v;
  }

  Future<void> _type()=>TvNearbyGate.during(_typeCode);
  Future<void> _typeCode() async {
    final ctrl=TextEditingController(), name=TextEditingController();
    var edited=false, closed=false; var asked='';
    final raw=await showDialog<String>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(S.t('tv.type')),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:ctrl,autofocus:true,textCapitalization:TextCapitalization.characters,
          decoration:InputDecoration(labelText:S.t('tv.code'),helperText:S.t('tv.codeHelp')),
          onChanged:(t) async {
            // Default name of the TV, proposed once the code is complete.
            final code=tvCodeFrom(t);
            if(code==null||code.length!=6||code==asked||edited)return;
            asked=code;
            final n=await widget.api.tvCodeName(code);
            if(n!=null&&!edited&&!closed&&asked==code)set(()=>name.text=n);
          }),
        const SizedBox(height:8),
        TextField(key:const ValueKey('tv-name'),controller:name,inputFormatters:[LengthLimitingTextInputFormatter(60)],onChanged:(_)=>edited=true,
          decoration:InputDecoration(labelText:S.t('tv.name'),helperText:S.t('tv.nameHelp'))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text),child:Text(S.t('tv.show')))])));
    closed=true;
    final chosen=name.text.trim();
    ctrl.dispose();name.dispose();
    if(raw==null||!mounted)return;
    final code=tvCodeFrom(raw);
    if(code==null){_say('tv.unknownCode');return;}
    await _approve(code,name:chosen);
  }

  /// « Renommer » (menu ⋮ of a screen).
  Future<void> _rename(Map<String,dynamic> d) async {
    final name=await _askName(S.t('tv.rename'),'${d['name']??''}');
    if(name==null||name.isEmpty||!mounted)return;
    try{
      await widget.api.renameDisplay(widget.eventId,'${d['id']}',name);
      _say('tv.renamed');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Identifier »: the TV shows its name in very large letters for 5 s.
  Future<void> _identify(Map<String,dynamic> d) async {
    try{
      await widget.api.identifyDisplay(widget.eventId,'${d['id']}');
      _say('tv.identifySent');
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  Future<void> _revoke(Map<String,dynamic> d) async {
    try{
      await widget.api.revokeDisplay(widget.eventId,'${d['id']}');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Retirer le bandeau SOS »: the person who paired the screen or an
  /// administrator; the SOS pill of the TV stays until the end of distress.
  Future<void> _clearSos(Map<String,dynamic> d) async {
    try{
      await widget.api.clearDisplayAlert(widget.eventId,'${d['id']}');
      _say('tv.sosCleared');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==403?'tv.sosForbidden':e.statusCode==401?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// Expired or revoked screens, hidden unless « Afficher les anciens ».
  bool _showOld=false;

  /// « Envoyer ma vue »: summary of what leaves (zoom, base map, layers)
  /// with the « Colonne des messages » box; null when cancelled.
  Future<bool?> _confirmView(TvView v,TvOptions? o,bool messages) async {
    var m=messages;
    final layers=o==null?const <String>[]:tvShownLayers(o.layers);
    return showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(S.t('tv.sendView')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(S.t('tv.sumZoom',{'z':v.zoom.toStringAsFixed(1).replaceAll('.',',')})),
        Text(S.t('tv.sumBase',{'b':v.basemapName.isEmpty?v.basemapId:v.basemapName})),
        Text(S.t('tv.sumLayers',{'l':layers.isEmpty?S.t('tv.sumNone'):[for(final k in layers)S.t(tvLayerLabels[k]!)].join(', ')})),
        CheckboxListTile(key:const ValueKey('tv-messages-box'),contentPadding:EdgeInsets.zero,value:m,onChanged:(x)=>set(()=>m=x??true),
          title:Text(S.t('tv.messagesColumn'))),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,m),child:Text(S.t('tv.send')))])));
  }

  /// « Messages : afficher / masquer » of this screen, at once, without
  /// sending the view again.
  Future<void> _messages(Map<String,dynamic> d) async {
    final show=d['messages']==false;
    try{
      await widget.api.setDisplayMessages(widget.eventId,'${d['id']}',show);
      _say(show?'tv.messagesShown':'tv.messagesHidden');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// « Envoyer ma vue » (view of the map of this device) or « Revenir à la
  /// vue par défaut » (null); no automatic return (30 Oct 2026).
  Future<void> _view(Map<String,dynamic> d,{required bool mine}) async {
    final v=mine?currentMapView?.call():null;
    if(mine&&v==null){_say('tv.noMap');return;}
    Map<String,dynamic>? json;
    if(v!=null){
      final o=currentMapOptions?.call();
      final m=await _confirmView(v,o,d['messages']!=false);
      if(m==null||!mounted)return;
      json=tvViewJson(v,options:o==null?null:(layers:o.layers,opacity:o.opacity,messages:m),from:myActorId,theme:themeMode.value);
      if(o==null)json['messages']=m;
    }
    try{
      await widget.api.sendDisplayView(widget.eventId,'${d['id']}',json);
      await _load();
      _say(mine?'tv.viewSent':'tv.autoSent');
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context); final all=_list;
    final list=all==null?null:tvVisibleScreens(all,showOld:_showOld);
    final old=all==null?0:all.length-tvVisibleScreens(all,showOld:false).length;
    return AbsorbPointer(absorbing:_busy,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
        Wrap(spacing:8,runSpacing:8,children:[
          if(canScanTvQr)FilledButton.icon(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:Text(S.t('tv.scan'))),
          OutlinedButton.icon(onPressed:_type,icon:const Icon(Icons.keyboard_outlined),label:Text(S.t('tv.type'))),
        ]),
        if(_busy)const Padding(padding:EdgeInsets.only(top:16),child:LinearProgressIndicator()),
        const SizedBox(height:16),
        Text(S.t('tv.list'),style:t.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w600,color:t.colorScheme.primary)),
        if(_offline)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.cloud_off),title:Text(S.t('event.offline')),
          trailing:OutlinedButton(onPressed:_load,child:Text(S.t('common.retry'))))
        else if(list==null)const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()))
        else if(list.isEmpty)ListTile(contentPadding:EdgeInsets.zero,title:Text(S.t('tv.none')))
        else for(final d in list)ListTile(contentPadding:EdgeInsets.zero,
          leading:Icon(d['active']==true?(d['alert']==true?Icons.sos:Icons.tv):Icons.tv_off,
            color:d['active']==true?(d['alert']==true?t.colorScheme.error:Colors.green):null),
          // Name as title, then last activity, the code in small, « vue de… ».
          title:Text(tvScreenTitle(d,S.t('tv.code'))),
          subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
            Text([d['active']==true?(d['last_seen'] is num?S.t('tv.lastSeen',{'t':tvWhen(d['last_seen'],lang:S.lang)}):S.t('tv.until',{'t':tvWhen(d['expires'],lang:S.lang)})):S.t(d['revoked']==true?'tv.revoked':'tv.expired'),
              if(d['active']==true&&d['messages']==false)S.t('tv.messagesOff')].join(' · ')),
            Text([if('${d['name']??''}'.trim().isNotEmpty)'${S.t('tv.code')} ${d['code']??''}',
              if(d['active']==true&&'${d['view_from']??''}'.isNotEmpty)S.t('tv.viewOf',{'who':d['view_from']})].join(' · '),
              style:t.textTheme.bodySmall),
          ]),
          trailing:d['active']==true?PopupMenuButton<String>(
            onSelected:(a){if(a=='view')_view(d,mine:true);if(a=='auto')_view(d,mine:false);if(a=='messages')_messages(d);if(a=='revoke')_revoke(d);if(a=='sos')_clearSos(d);if(a=='rename')_rename(d);if(a=='identify')_identify(d);},
            itemBuilder:(_)=>[
              PopupMenuItem(value:'view',child:ListTile(leading:const Icon(Icons.cast),title:Text(S.t('tv.sendView')),subtitle:Text(S.t('tv.sendViewHelp2')))),
              PopupMenuItem(value:'identify',child:ListTile(leading:const Icon(Icons.highlight_alt),title:Text(S.t('tv.identify')))),
              PopupMenuItem(value:'rename',child:ListTile(leading:const Icon(Icons.edit_outlined),title:Text(S.t('tv.rename')))),
              PopupMenuItem(value:'auto',child:ListTile(leading:const Icon(Icons.fit_screen),title:Text(S.t('tv.auto')))),
              PopupMenuItem(value:'messages',child:ListTile(leading:Icon(d['messages']==false?Icons.chat_outlined:Icons.speaker_notes_off_outlined),
                title:Text(S.t(d['messages']==false?'tv.messagesShow':'tv.messagesHide')))),
              PopupMenuItem(value:'sos',enabled:d['can_clear_alert']!=false,
                child:ListTile(leading:const Icon(Icons.sos),title:Text(S.t('tv.clearSos')))),
              PopupMenuItem(value:'revoke',child:ListTile(leading:const Icon(Icons.tv_off),title:Text(S.t('tv.revoke')))),
            ]):null),
        if(old>0)Align(alignment:Alignment.centerLeft,child:OutlinedButton(key:const ValueKey('tv-show-old'),onPressed:()=>setState(()=>_showOld=!_showOld),
          child:Text(_showOld?S.t('tv.hideOld'):S.t('tv.showOld',{'n':old})))),
      ]));
  }
}
