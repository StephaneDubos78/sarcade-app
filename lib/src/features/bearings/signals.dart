/// Signals searched by the bearings (note « Relevé : liste des signaux avec
/// fréquences par défaut », validated on 29 Oct 2026): the signals of the
/// event first, then the default frequencies of the server (editable by the
/// administrator), then « Autre… ». Each signal is real or an exercise.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'bearing_models.dart';

class SignalChoice {
  final String label; final double? frequencyMhz; final bool exercise; final bool hidden;
  const SignalChoice({required this.label,this.frequencyMhz,this.exercise=false,this.hidden=false});

  /// Name kept on the bearings (« 121,375 MHz · Balise d'exercice »): the
  /// search the bearings belong to, one colour per name.
  String get name=>frequencyMhz==null?label:label.isEmpty?formatMhz(frequencyMhz!):'${formatMhz(frequencyMhz!)} · $label';

  factory SignalChoice.fromJson(Map<String,dynamic> j)=>SignalChoice(label:(j['label'] as String?)?.trim()??'',
    frequencyMhz:(j['frequency_mhz'] as num?)?.toDouble(),exercise:j['exercise']==true,hidden:j['hidden']==true);
  Map<String,dynamic> toJson()=>{'label':label,'frequency_mhz':frequencyMhz,'exercise':exercise,'hidden':hidden};
  SignalChoice copyWith({String? label,double? frequencyMhz,bool? exercise,bool? hidden})=>SignalChoice(label:label??this.label,
    frequencyMhz:frequencyMhz??this.frequencyMhz,exercise:exercise??this.exercise,hidden:hidden??this.hidden);
}

/// Initial list, also used when the server is not reachable.
const defaultSignals=[
  SignalChoice(label:'Balise de détresse réelle',frequencyMhz:121.5),
  SignalChoice(label:'Balise d’exercice',frequencyMhz:121.375,exercise:true),
  SignalChoice(label:'Cospas-Sarsat',frequencyMhz:406.0),
];

/// « 121,375 MHz »: three decimals, French comma.
String formatMhz(double f)=>'${f.toStringAsFixed(3).replaceAll('.',',')} MHz';

/// Frequency typed in MHz (« 121.375 », « 121,375 »), null when invalid.
double? parseMhz(String text){
  final v=double.tryParse(text.replaceAll(',','.').replaceAll(RegExp(r'\s|mhz',caseSensitive:false),''));
  return v==null||v<1||v>10000?null:v;
}

List<SignalChoice> decodeSignals(String? raw){
  if(raw==null||raw.isEmpty)return defaultSignals;
  try{
    final j=jsonDecode(raw);
    final list=(j is Map?j['signals']:j) as List;
    final out=[for(final e in list)if(e is Map)SignalChoice.fromJson(Map<String,dynamic>.from(e))];
    return out.isEmpty?defaultSignals:out;
  }catch(_){return defaultSignals;}
}
String encodeSignals(List<SignalChoice> list)=>jsonEncode({'signals':[for(final s in list)s.toJson()]});

/// The list shown in the bearing sheet: signals of the event (most recent
/// first, nature taken from their last bearing), then the visible defaults
/// not used yet. [extra]: signals typed with « Autre… » not yet saved.
List<SignalChoice> signalMenu(Iterable<Bearing> bearings,List<SignalChoice> defaults,{List<SignalChoice> extra=const []}){
  final sorted=[...bearings]..sort((a,b)=>b.takenAt.compareTo(a.takenAt));
  final out=<SignalChoice>[]; final seen=<String>{};
  void add(SignalChoice s){if(s.name.isNotEmpty&&seen.add(s.name))out.add(s);}
  for(final s in extra){add(s);}
  for(final b in sorted){
    if(b.search.isEmpty)continue;
    final d=defaults.where((s)=>s.name==b.search).firstOrNull;
    add(d??SignalChoice(label:b.search,exercise:b.exercise));
  }
  for(final s in defaults){if(!s.hidden)add(s);}
  return out;
}

/// « EXERCICE »: never mistake an exercise for a real distress.
class ExerciseBadge extends StatelessWidget {
  const ExerciseBadge({super.key});
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:1),
    decoration:BoxDecoration(color:const Color(0xFFFFE8CC),borderRadius:BorderRadius.circular(6),border:Border.all(color:const Color(0xFFE8710A))),
    child:const Text('EXERCICE',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:Color(0xFFB45309),letterSpacing:0.5)));
}
