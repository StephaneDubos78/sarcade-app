import 'package:flutter/material.dart';
import '../../ui/overlay_page.dart';
import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';
import '../aprs/aprs_page.dart';
import 'quick_messages_editor.dart';
import '../../services/event_names.dart';

/// Paramètres › Événement (PCO): settings of the active event kept by the
/// server, applied at once and written in the logbook by the server —
/// « old » stations threshold, predefined messages, APRS followed. The
/// local radio transmission and its callsign moved to the APRS screen
/// (lot 5, decision of 30 Oct 2026, 2 h 47).
class EventSettingsSection extends StatefulWidget {
  final SarcadeApi api; final String eventId, actorId;
  const EventSettingsSection({super.key,required this.api,required this.eventId,required this.actorId});
  @override State<EventSettingsSection> createState()=>_EventSettingsSectionState();
}

class _EventSettingsSectionState extends State<EventSettingsSection> {
  Map<String,dynamic>? _s; String? _error; bool _busy=false;
  static const oldChoices=[30,60,120,240,480,1440];

  @override void initState(){super.initState();_load();}

  Future<void> _load() async {
    try{
      final e=await widget.api.event(widget.eventId);
      final s=Map<String,dynamic>.from(e['settings'] as Map? ?? {});
      if(!mounted)return;
      setState((){_s=s;_error=null;});
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
    final list=await showOverlayPage<List<String>>(context,(_)=>QuickMessagesEditor(initial:initial));
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
        :Column(children:[Text(S.t('event.offline')),OutlinedButton(onPressed:_load,child:Text(S.t('common.retry')))]));
    }
    final old=(s['position_old_min'] as num?)?.toInt()??120;
    String dur(int m)=>m%60==0?'${m~/60} h':'$m min';
    return AbsorbPointer(absorbing:_busy,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:12),child:EventNameBuilder(api:widget.api,eventId:widget.eventId,placeholder:S.t('event.this'),
        builder:(_,name)=>Text(S.t('event.intro',{'event':name})))),
      _row(S.t('event.oldThreshold'),help:S.t('event.oldThresholdHelp'),child:DropdownButton<int>(value:oldChoices.contains(old)?old:120,
        items:[for(final m in oldChoices)DropdownMenuItem(value:m,child:Text(dur(m)))],
        onChanged:(v){if(v!=null)_patch({'position_old_min':v});})),
      _row(S.t('event.quick'),help:S.t('event.quickHelp',{'n':(s['quick_messages'] as List?)?.length??0}),
        child:OutlinedButton(onPressed:_editQuick,child:Text(S.t('event.edit')))),
      _row(S.t('event.aprsFollowed'),help:[S.t('event.aprsFollowedHelp',{'g':(s['aprs_groups'] as List?)?.length??0,'c':(s['aprs_callsigns'] as List?)?.length??0}),
          if(s['aprs_tx_rf']==true)S.t('event.aprsTxOn',{'call':'${s['aprs_tx_callsign']??'—'}'})].join(' · '),
        child:OutlinedButton(onPressed:()=>showOverlayPage<void>(context,(_)=>AprsPage(api:widget.api,eventId:widget.eventId,actorId:widget.actorId)).then((_)=>_load()),
          child:Text(S.t('diagnostics.open')))),
    ]));
  }
}
