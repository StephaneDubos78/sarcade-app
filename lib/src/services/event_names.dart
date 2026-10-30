/// Name of an event instead of its identifier (revue d'ergonomie n° 60):
/// « Réglages de Exercice ADRASEC 78 Versailles », not of a UUID. The
/// identifier stays in the copyable report of the Diagnostic only.
library;

import 'package:flutter/widgets.dart';

import 'sarcade_api.dart';

final Map<String,String> _names={};

/// Name of [eventId] in a list of events of the server; null if absent.
String? eventNameIn(List<Map<String,dynamic>> events,String eventId){
  for(final e in events){
    if('${e['id']}'==eventId){
      final n='${e['name']??''}'.trim();
      return n.isEmpty?null:n;
    }
  }
  return null;
}

/// Line of the copyable report: « Exercice … (a79364b2-…) ».
String eventReportValue(String? name,String eventId)=>name==null?eventId:'$name ($eventId)';

/// Known name, or null (not loaded yet, offline, older server).
String? knownEventName(String eventId)=>_names[eventId];

Future<String?> loadEventName(SarcadeApi? api,String eventId) async {
  final known=_names[eventId];
  if(known!=null||api==null)return known;
  try{
    final n=eventNameIn(await api.events(includeClosed:true),eventId);
    if(n!=null)_names[eventId]=n;
    return n;
  }catch(_){
    return null;
  }
}

/// Builds with the name of the event; its identifier as long as the name is
/// unknown (loading, offline, older server).
class EventNameBuilder extends StatefulWidget {
  final SarcadeApi? api; final String eventId;
  final Widget Function(BuildContext context,String name) builder;
  const EventNameBuilder({super.key,required this.api,required this.eventId,required this.builder});
  @override State<EventNameBuilder> createState()=>_EventNameBuilderState();
}

class _EventNameBuilderState extends State<EventNameBuilder> {
  @override void initState(){
    super.initState();
    if(knownEventName(widget.eventId)==null){
      loadEventName(widget.api,widget.eventId).then((n){if(n!=null&&mounted)setState((){});});
    }
  }
  @override Widget build(BuildContext context)=>widget.builder(context,knownEventName(widget.eventId)??widget.eventId);
}
