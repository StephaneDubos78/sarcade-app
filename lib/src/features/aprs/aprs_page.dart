import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';
import 'aprs_models.dart';

/// PCO screen « APRS de l'événement » (vault note « APRS »): callsign groups
/// followed by the event, callsigns added for it, local radio transmission,
/// state of the links. Callsign groups are also managed here until the
/// administration console exists. Needs the server: nothing is queued.
class AprsPage extends StatefulWidget {
  final SarcadeApi api; final String eventId, actorId;
  const AprsPage({super.key,required this.api,required this.eventId,required this.actorId});
  @override State<AprsPage> createState()=>_AprsPageState();
}

class _AprsPageState extends State<AprsPage> {
  List<Map<String,dynamic>> _groups=[];
  List<String> _followedGroups=[], _added=[], _effective=[];
  bool _txRf=false, _loading=true, _ended=false;
  Map<String,dynamic>? _status; String? _error;
  final _addCtrl=TextEditingController();
  Timer? _statusTimer;

  @override void initState(){
    super.initState();
    _load();
    _statusTimer=Timer.periodic(const Duration(seconds:15),(_)=>_loadStatus());
  }
  @override void dispose(){_statusTimer?.cancel();_addCtrl.dispose();super.dispose();}

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
        _ended=event['ended_at']!=null;
        _effective=results[2] as List<String>;
      });
      await _loadStatus();
    }catch(e){
      if(mounted)setState(()=>_error=S.t('aprs.offline'));
    }finally{
      if(mounted)setState(()=>_loading=false);
    }
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
        if(r.invalid.isNotEmpty){_snack(S.t('aprs.invalid',{'list':r.invalid.join(', ')}));return;}
        await widget.api.saveAprsGroup(id:group?['id'] as String?,name:nameText,callsigns:r.valid,actorId:widget.actorId);
      }
      await _load();
    }on SarcadeHttpException catch(e){
      _snack(S.t('aprs.refused',{'error':e.body.isEmpty?'HTTP ${e.statusCode}':e.body}));
    }catch(_){_snack(S.t('aprs.offline'));}
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
      appBar:AppBar(title:Text(S.t('aprs.title')),actions:[IconButton(tooltip:S.t('aprs.reload'),onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:_loading&&_groups.isEmpty?const Center(child:CircularProgressIndicator())
        :_error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.cloud_off,size:40),const SizedBox(height:8),Text(_error!,textAlign:TextAlign.center),
            TextButton(onPressed:_load,child:Text(S.t('aprs.reload')))])))
        :ListView(padding:const EdgeInsets.symmetric(vertical:8),children:[
          if(_ended)Material(color:theme.colorScheme.tertiaryContainer,child:Padding(padding:const EdgeInsets.all(12),child:Text(S.t('aprs.ended')))),
          // Links
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Text(S.t('aprs.links'),style:theme.textTheme.titleSmall)),
          _link('aprs.is',_status?['aprs_is'] is Map?Map<String,dynamic>.from(_status!['aprs_is'] as Map):null),
          _link('aprs.radio',_status?['radio'] is Map?Map<String,dynamic>.from(_status!['radio'] as Map):null),
          Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(
            _effective.isEmpty?S.t('aprs.followedNone'):S.t('aprs.followed',{'list':_effective.join(', ')}),
            style:theme.textTheme.bodySmall)),
          const Divider(height:24),
          // Groups
          Padding(padding:const EdgeInsets.fromLTRB(16,0,8,0),child:Row(children:[
            Expanded(child:Text(S.t('aprs.groups'),style:theme.textTheme.titleSmall)),
            TextButton.icon(onPressed:()=>_editGroup(null),icon:const Icon(Icons.add),label:Text(S.t('aprs.groupNew'))),
          ])),
          if(_groups.isEmpty)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Text(S.t('aprs.groupsNone'),style:theme.textTheme.bodySmall)),
          for(final g in _groups)CheckboxListTile(
            value:_followedGroups.contains(g['id']),
            onChanged:_ended?null:(v)=>_toggleGroup('${g['id']}',v==true),
            title:Text('${g['name']}'),
            subtitle:Text(stringList(g['callsigns']).join(' · ')),
            secondary:IconButton(tooltip:S.t('aprs.groupEdit'),onPressed:()=>_editGroup(g),icon:const Icon(Icons.edit_outlined)),
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
            IconButton(tooltip:S.t('aprs.add'),onPressed:_ended?null:_addCallsigns,icon:const Icon(Icons.add_circle_outline)),
          ])),
          const Divider(height:24),
          SwitchListTile(
            value:_txRf,onChanged:_ended?null:_setTx,
            title:Text(S.t('aprs.txRf')),subtitle:Text(S.t('aprs.txRfHelp')),
          ),
        ]),
    );
  }
}
