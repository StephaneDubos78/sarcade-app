import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';
import '../aprs/aprs_page.dart';
import 'quick_messages_editor.dart';

/// Paramètres › Événement (PCO): settings of the active event kept by the
/// server, applied at once and written in the logbook by the server —
/// local radio transmission and its callsign (chosen by the PCO, the
/// ADRASEC has none), « old » stations threshold, APRS followed.
class EventSettingsSection extends StatefulWidget {
  final SarcadeApi api; final String eventId, actorId;
  const EventSettingsSection({super.key,required this.api,required this.eventId,required this.actorId});
  @override State<EventSettingsSection> createState()=>_EventSettingsSectionState();
}

class _EventSettingsSectionState extends State<EventSettingsSection> {
  Map<String,dynamic>? _s; String? _error; bool _busy=false;
  final _call=TextEditingController();
  static const oldChoices=[30,60,120,240,480,1440];

  @override void initState(){super.initState();_load();}
  @override void dispose(){_call.dispose();super.dispose();}

  Future<void> _load() async {
    try{
      final e=await widget.api.event(widget.eventId);
      final s=Map<String,dynamic>.from(e['settings'] as Map? ?? {});
      if(!mounted)return;
      setState((){_s=s;_error=null;_call.text='${s['aprs_tx_callsign']??''}';});
    }catch(e){
      if(mounted)setState(()=>_error='$e');
    }
  }

  Future<void> _patch(Map<String,dynamic> p) async {
    setState(()=>_busy=true);
    try{
      final e=await widget.api.patchEventSettings(widget.eventId,widget.actorId,p);
      final s=Map<String,dynamic>.from(e['settings'] as Map? ?? {});
      if(mounted)setState(()=>_s=s);
    }on SarcadeHttpException catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(e.statusCode==403?'event.forbidden':'event.refused',{'error':'${e.statusCode}'}))));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('event.offline'))));
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  /// Predefined messages of the event (ATAK 6): an editable list.
  Future<void> _editQuick() async {
    final initial=((_s?['quick_messages'] as List?)??const []).whereType<String>().toList();
    final list=await Navigator.push<List<String>>(context,MaterialPageRoute(builder:(_)=>QuickMessagesEditor(initial:initial)));
    if(list!=null)await _patch({'quick_messages':list});
  }

  Widget _row(String label,{String? help,required Widget child}){
    final t=Theme.of(context);
    return Column(children:[
      Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w600)),
          if(help!=null)Text(help,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        ])),
        const SizedBox(width:12),
        child,
      ])),
      const Divider(height:1),
    ]);
  }

  @override
  Widget build(BuildContext context){
    final s=_s;
    if(s==null){
      return Padding(padding:const EdgeInsets.all(16),child:_error==null?const Center(child:CircularProgressIndicator())
        :Column(children:[Text(S.t('event.offline')),TextButton(onPressed:_load,child:Text(S.t('common.retry')))]));
    }
    final old=(s['position_old_min'] as num?)?.toInt()??120;
    String dur(int m)=>m%60==0?'${m~/60} h':'$m min';
    return AbsorbPointer(absorbing:_busy,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:12),child:Text(S.t('event.intro',{'event':widget.eventId}))),
      _row(S.t('event.radioTx'),help:S.t('event.radioTxHelp'),child:Switch(value:s['aprs_tx_rf']==true,
        onChanged:(v)=>_patch({'aprs_tx_rf':v}))),
      _row(S.t('event.radioCallsign'),help:S.t('event.radioCallsignHelp'),child:SizedBox(width:220,child:Row(children:[
        Expanded(child:TextField(controller:_call,textCapitalization:TextCapitalization.characters,
          decoration:InputDecoration(isDense:true,hintText:'F4ABC',border:OutlineInputBorder(borderRadius:BorderRadius.circular(8))))),
        TextButton(onPressed:()=>_patch({'aprs_tx_callsign':_call.text.trim().isEmpty?null:_call.text.trim()}),child:Text(S.t('event.apply'))),
      ]))),
      _row(S.t('event.oldThreshold'),help:S.t('event.oldThresholdHelp'),child:DropdownButton<int>(value:oldChoices.contains(old)?old:120,
        items:[for(final m in oldChoices)DropdownMenuItem(value:m,child:Text(dur(m)))],
        onChanged:(v){if(v!=null)_patch({'position_old_min':v});})),
      _row(S.t('event.quick'),help:S.t('event.quickHelp',{'n':(s['quick_messages'] as List?)?.length??0}),
        child:TextButton(onPressed:_editQuick,child:Text(S.t('event.edit')))),
      _row(S.t('event.aprsFollowed'),help:S.t('event.aprsFollowedHelp',{'g':(s['aprs_groups'] as List?)?.length??0,'c':(s['aprs_callsigns'] as List?)?.length??0}),
        child:TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>AprsPage(api:widget.api,eventId:widget.eventId,actorId:widget.actorId))).then((_)=>_load()),
          child:Text(S.t('diagnostics.open')))),
    ]));
  }
}
