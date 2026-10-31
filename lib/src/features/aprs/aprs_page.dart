import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import '../../models/position.dart';
import '../../services/sarcade_api.dart';
import '../measure/coordinates.dart';
import 'aprs_models.dart';
import '../../ui/action_buttons.dart';
import '../../ui/link_status.dart';

/// PCO screen « APRS de l'événement » (vault note « APRS »): callsign groups
/// followed by the event, callsigns added for it, local radio transmission,
/// state of the links. Callsign groups are also managed here until the
/// administration console exists. Needs the server: nothing is queued.
/// Lot 5 (30 Oct 2026, all points validated): followed stations as chips
/// (green dot: heard within the hour), help for the radio Gateway, added
/// callsigns as removable chips, a station touched shows its last position,
/// source and aprs.fi link, « Voir sur la carte »; local radio transmission
/// and its callsign live here only (removed from Paramètres › Événement).
class AprsPage extends StatefulWidget {
  final SarcadeApi api; final String eventId, actorId;
  /// « Voir sur la carte » (null: not offered).
  final void Function(LatLng point,String label)? onShowOnMap;
  const AprsPage({super.key,required this.api,required this.eventId,required this.actorId,this.onShowOnMap});
  @override State<AprsPage> createState()=>_AprsPageState();
}

class _AprsPageState extends State<AprsPage> {
  List<Map<String,dynamic>> _groups=[];
  List<String> _followedGroups=[], _added=[], _effective=[];
  bool _txRf=false, _loading=true, _ended=false;
  Map<String,dynamic>? _status; String? _error;
  final _addCtrl=TextEditingController(), _txCall=TextEditingController();
  Timer? _statusTimer;
  List<SarcadePosition> _heard=[];

  @override void initState(){
    super.initState();
    _load();
    _statusTimer=Timer.periodic(const Duration(seconds:15),(_)=>_loadStatus());
  }
  @override void dispose(){_statusTimer?.cancel();_addCtrl.dispose();_txCall.dispose();super.dispose();}

  void _snack(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}

  Future<void> _load() async {
    setState((){_loading=true;_error=null;});
    try{
      final results=await Future.wait([widget.api.aprsGroups(),widget.api.event(widget.eventId),widget.api.followedCallsigns(widget.eventId)]);
      final event=results[1] as Map<String,dynamic>;
      final settings=event['settings'] is Map?Map<String,dynamic>.from(event['settings'] as Map):<String,dynamic>{};
      if(!mounted)return;
      setState((){
        _groups=(results[0] as List<Map<String,dynamic>>)..sort((a,b)=>'${a['name']}'.compareTo('${b['name']}'));
        _followedGroups=stringList(settings['aprs_groups']);
        _added=stringList(settings['aprs_callsigns']);
        _txRf=settings['aprs_tx_rf']==true;
        _txCall.text='${settings['aprs_tx_callsign']??''}';
        _ended=event['ended_at']!=null;
        _effective=results[2] as List<String>;
      });
      await _loadStatus();
      unawaited(_loadHeard());
    }catch(e){
      if(mounted)setState(()=>_error=S.t('aprs.offline'));
    }finally{
      if(mounted)setState(()=>_loading=false);
    }
  }

  /// APRS positions of the event (last per station): green dots, details.
  Future<void> _loadHeard() async {
    try{
      final list=await widget.api.latestPositions(widget.eventId);
      if(mounted)setState(()=>_heard=list.where((p)=>p.isAprs||(p.callsign?.isNotEmpty??false)).toList());
    }catch(_){/* kept as is */}
  }

  Iterable<({String callsign,DateTime time})> get _heardTimes=>[for(final p in _heard)(callsign:p.callsign??p.label,time:p.time.toUtc())];

  SarcadePosition? _lastOf(String entry){
    SarcadePosition? best;
    for(final p in _heard){if(callsignMatches(entry,p.callsign??p.label)&&(best==null||p.time.isAfter(best.time)))best=p;}
    return best;
  }

  Future<void> _open(String url) async {
    try{await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);}catch(_){_snack(url);}
  }

  /// A station touched: last position, source, aprs.fi and QRZ.com links.
  void _station(String entry){
    final p=_lastOf(entry); final now=DateTime.now().toUtc();
    showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(entry,style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w700)),
        const SizedBox(height:6),
        if(p==null)Text(S.t('aprs.neverHeard'))
        else ...[
          Text(formatDd(LatLng(p.lat,p.lon)),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
          Text([if(p.callsign!=null&&p.callsign!=entry)p.callsign!,
            S.t(p.aprsVia=='rf'?'aprs.sourceRadio':'aprs.sourceInternet'),
            S.t('aprs.heardAgo',{'min':now.difference(p.time.toUtc()).inMinutes})].join(' · ')),
          if(p.aprsPath?.isNotEmpty==true)Text(p.aprsPath!,style:const TextStyle(fontSize:12,fontFamily:'monospace')),
        ],
        const SizedBox(height:10),
        Wrap(spacing:8,runSpacing:8,children:[
          if(p!=null&&widget.onShowOnMap!=null)FilledButton.icon(onPressed:(){Navigator.pop(c);final nav=Navigator.of(context);if(nav.canPop())nav.pop();
            widget.onShowOnMap!(LatLng(p.lat,p.lon),entry);},icon:const Icon(Icons.map_outlined),label:Text(S.t('aprs.showOnMap'))),
          OutlinedButton.icon(onPressed:()=>_open(aprsFiUrl(p?.callsign??entry)),icon:const Icon(Icons.open_in_new),label:const Text('aprs.fi')),
          OutlinedButton.icon(onPressed:()=>_open(qrzUrl(entry)),icon:const Icon(Icons.open_in_new),label:Text(S.t('station.qrz'))),
        ]),
      ]))));
  }

  Future<void> _loadStatus() async {
    try{final s=await widget.api.aprsStatus();if(mounted)setState(()=>_status=s);}catch(_){/* kept as is */}
  }

  /// Saves the event settings; the server logs the change in the logbook.
  Future<void> _patch(Map<String,dynamic> settings) async {
    try{
      await widget.api.patchEventSettings(widget.eventId,widget.actorId,settings);
      final effective=await widget.api.followedCallsigns(widget.eventId);
      if(mounted)setState(()=>_effective=effective);
      unawaited(Future.delayed(const Duration(seconds:3),_loadStatus));
    }on SarcadeHttpException catch(e){
      _snack(e.statusCode==409?S.t('aprs.ended'):S.t('aprs.refused',{'error':e.body.isEmpty?'HTTP ${e.statusCode}':e.body}));
      await _load();
    }catch(_){
      _snack(S.t('aprs.offline'));
      await _load();
    }
  }

  Future<void> _toggleGroup(String id,bool on) async {
    setState((){if(on){_followedGroups=[..._followedGroups,id];}else{_followedGroups=_followedGroups.where((g)=>g!=id).toList();}});
    await _patch({'aprs_groups':_followedGroups});
  }

  Future<void> _addCallsigns() async {
    final r=parseCallsigns(_addCtrl.text);
    if(r.invalid.isNotEmpty){_snack(S.t('aprs.invalid',{'list':r.invalid.join(', ')}));return;}
    if(r.valid.isEmpty)return;
    setState((){_added=[..._added,...r.valid.where((c)=>!_added.contains(c))];_addCtrl.clear();});
    await _patch({'aprs_callsigns':_added});
  }

  Future<void> _removeCallsign(String c) async {
    setState(()=>_added=_added.where((x)=>x!=c).toList());
    await _patch({'aprs_callsigns':_added});
  }

  Future<void> _setTx(bool on) async {
    setState(()=>_txRf=on);
    await _patch({'aprs_tx_rf':on});
  }

  Future<void> _setTxCall() async {
    final raw=_txCall.text.trim();
    if(raw.isNotEmpty&&cleanCallsign(raw)==null){_snack(S.t('aprs.invalid',{'list':raw}));return;}
    await _patch({'aprs_tx_callsign':raw.isEmpty?null:cleanCallsign(raw)});
    _snack(S.t('aprs.txCallSaved'));
  }

  Future<void> _editGroup(Map<String,dynamic>? group) async {
    final name=TextEditingController(text:group==null?'':'${group['name']}');
    final calls=TextEditingController(text:group==null?'':stringList(group['callsigns']).join(' '));
    final result=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t(group==null?'aprs.groupNew':'aprs.groupEdit')),
      content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,autofocus:group==null,decoration:InputDecoration(labelText:S.t('aprs.groupName'))),
        const SizedBox(height:12),
        TextField(controller:calls,minLines:2,maxLines:5,textCapitalization:TextCapitalization.characters,
          decoration:InputDecoration(labelText:S.t('aprs.groupCallsigns'),helperText:S.t('aprs.ssidHelp'),helperMaxLines:3)),
      ])),
      actions:[
        if(group!=null)TextButton(onPressed:()=>Navigator.pop(c,'delete'),child:Text(S.t('aprs.groupDelete'),style:TextStyle(color:Theme.of(c).colorScheme.error))),
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,'save'),child:Text(S.t('common.save'))),
      ]));
    final nameText=name.text.trim(), callsText=calls.text;
    name.dispose(); calls.dispose();
    if(result==null||!mounted)return;
    try{
      if(result=='delete'){
        final gr=group!;
        final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
          content:Text(S.t('aprs.groupDeleteConfirm',{'name':'${gr['name']}'})),
          actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
            FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('aprs.groupDelete')))]));
        if(ok!=true)return;
        await widget.api.deleteAprsGroup('${gr['id']}');
        if(_followedGroups.contains(gr['id'])){
          _followedGroups=_followedGroups.where((g)=>g!=gr['id']).toList();
          await _patch({'aprs_groups':_followedGroups});
        }
      }else{
        final r=parseCallsigns(callsText);
        if(nameText.isEmpty){_snack(S.t('aprs.nameRequired'));return;}
        if(groupNameTaken(nameText,_groups,ownId:group?['id'] as String?)){_snack(S.t('aprs.nameTaken',{'name':nameText}));return;}
        if(r.invalid.isNotEmpty){_snack(S.t('aprs.invalid',{'list':r.invalid.join(', ')}));return;}
        await widget.api.saveAprsGroup(id:group?['id'] as String?,name:nameText,callsigns:r.valid,actorId:widget.actorId);
      }
      await _load();
    }on SarcadeHttpException catch(e){
      _snack(e.statusCode==409&&e.body.contains('aprs_group_name_taken')?S.t('aprs.nameTaken',{'name':nameText})
        :S.t('aprs.refused',{'error':e.body.isEmpty?'HTTP ${e.statusCode}':e.body}));
    }catch(_){_snack(S.t('aprs.offline'));}
  }

  /// Followed stations as chips: green dot heard within the hour, grey else.
  Widget _followedChips(ThemeData theme){
    final now=DateTime.now().toUtc();
    if(_effective.isEmpty)return Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(S.t('aprs.followedNone'),style:theme.textTheme.bodySmall));
    return Padding(padding:const EdgeInsets.fromLTRB(16,4,16,0),child:Wrap(spacing:6,runSpacing:6,children:[
      for(final c in _effective)ActionChip(key:ValueKey('aprs-station-$c'),onPressed:()=>_station(c),
        avatar:Icon(Icons.circle,size:12,color:heardRecently(lastHeard(c,_heardTimes),now)?Colors.green:Colors.grey),label:Text(c)),
    ]));
  }

  Widget _link(String key,Map<String,dynamic>? link){
    final state=linkState(link);
    final color=state=='connected'?Colors.green:state=='waiting'?Colors.orange:Colors.grey;
    final packets=link?['packets'];
    return ListTile(dense:true,
      leading:Icon(Icons.circle,size:14,color:color),
      title:Text(S.t(key)),
      subtitle:Text([S.t('aprs.link.$state'),if(packets!=null)S.t('aprs.packets',{'n':packets}),if('${link?['detail']??''}'.isNotEmpty)'${link!['detail']}'].join(' · ')),
    );
  }

  @override
  Widget build(BuildContext context){
    final theme=Theme.of(context);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('aprs.title')),actions:[IconButton(tooltip:S.t('aprs.reload'),onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:_loading&&_groups.isEmpty?const Center(child:CircularProgressIndicator())
        :_error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.cloud_off,size:40),const SizedBox(height:8),Text(_error!,textAlign:TextAlign.center),
            OutlinedButton(onPressed:_load,child:Text(S.t('aprs.reload')))])))
        :ListView(padding:const EdgeInsets.symmetric(vertical:8),children:[
          if(_ended)Material(color:theme.colorScheme.tertiaryContainer,child:Padding(padding:const EdgeInsets.all(12),child:Text(S.t('aprs.ended')))),
          // Links
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Text(S.t('aprs.links'),style:theme.textTheme.titleSmall)),
          _link('aprs.is',_status?['aprs_is'] is Map?Map<String,dynamic>.from(_status!['aprs_is'] as Map):null),
          _link('aprs.radio',_status?['radio'] is Map?Map<String,dynamic>.from(_status!['radio'] as Map):null),
          if(linkState(_status?['radio'] is Map?Map<String,dynamic>.from(_status!['radio'] as Map):null)!='connected')
            Padding(padding:const EdgeInsets.fromLTRB(16,0,16,4),child:ExpansionTile(key:const ValueKey('aprs-gateway-help'),
              tilePadding:EdgeInsets.zero,dense:true,leading:const Icon(Icons.help_outline,size:20),title:Text(S.t('aprs.gatewayHelpTitle')),
              children:[Align(alignment:Alignment.centerLeft,child:Text(S.t('aprs.gatewayHelp'),style:theme.textTheme.bodySmall))])),
          const Divider(height:24),
          Padding(padding:const EdgeInsets.fromLTRB(16,0,16,0),child:Text(S.t('aprs.stations'),style:theme.textTheme.titleSmall)),
          _followedChips(theme),
          const Divider(height:24),
          // Groups
          Padding(padding:const EdgeInsets.fromLTRB(16,0,8,0),child:Row(children:[
            Expanded(child:Text(S.t('aprs.groups'),style:theme.textTheme.titleSmall)),
            FilledButton.icon(onPressed:()=>_editGroup(null),icon:const Icon(Icons.add),label:Text(S.t('aprs.groupNew'))),
          ])),
          if(_groups.isEmpty)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(S.t('aprs.groupsNone'),style:theme.textTheme.bodySmall)),
          for(final g in _groups)CheckboxListTile(
            value:_followedGroups.contains(g['id']),
            onChanged:_ended?null:(v)=>_toggleGroup('${g['id']}',v==true),
            title:Text('${g['name']}'),
            subtitle:Text(stringList(g['callsigns']).join(' · ')),
            secondary:RoundIconButton(tooltip:S.t('aprs.groupEdit'),onPressed:()=>_editGroup(g),icon:Icons.edit_outlined),
            controlAffinity:ListTileControlAffinity.leading,
          ),
          const Divider(height:24),
          // Callsigns added for this event
          Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(S.t('aprs.added'),style:theme.textTheme.titleSmall)),
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Wrap(spacing:6,runSpacing:6,children:[
            for(final c in _added)InputChip(label:Text(c),onDeleted:_ended?null:()=>_removeCallsign(c)),
          ])),
          Padding(padding:const EdgeInsets.fromLTRB(16,8,8,0),child:Row(children:[
            Expanded(child:TextField(controller:_addCtrl,enabled:!_ended,textCapitalization:TextCapitalization.characters,
              decoration:InputDecoration(labelText:S.t('aprs.addCallsign'),helperText:S.t('aprs.ssidHelp'),helperMaxLines:2),
              onSubmitted:(_)=>_addCallsigns())),
            RoundIconButton(tooltip:S.t('aprs.add'),onPressed:_ended?null:_addCallsigns,icon:Icons.add),
          ])),
          const Divider(height:24),
          // Local radio transmission and its callsign: only here (lot 5).
          SwitchListTile(key:const ValueKey('aprs-tx'),
            value:_txRf,onChanged:_ended?null:_setTx,
            title:Text(S.t('aprs.txRf')),subtitle:Text(S.t('aprs.txRfHelp')),
          ),
          Padding(padding:const EdgeInsets.fromLTRB(16,0,8,0),child:Row(children:[
            Expanded(child:TextField(key:const ValueKey('aprs-tx-callsign'),controller:_txCall,enabled:!_ended,textCapitalization:TextCapitalization.characters,
              decoration:InputDecoration(labelText:S.t('aprs.txCall'),hintText:'F4ABC',helperText:S.t('aprs.txCallHelp'),helperMaxLines:2),
              onSubmitted:(_)=>_setTxCall())),
            FilledButton(onPressed:_ended?null:_setTxCall,child:Text(S.t('event.apply'))),
          ])),
        ]),
    );
  }
}
