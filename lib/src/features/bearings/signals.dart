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

/// Apostrophes and spaces made the same (« d’exercice » = « d'exercice »).
String normalizeSignalName(String s)=>s.replaceAll(RegExp('[\u2019\u2018\u02BC`´]'),"'").replaceAll(RegExp(r'\s+'),' ').trim().toLowerCase();

/// Frequency read at the start of a signal name (« 121,375 MHz · … »).
double? frequencyOfName(String name){
  final m=RegExp(r'^\s*(\d{1,5}(?:[.,]\d+)?)\s*MHz',caseSensitive:false).firstMatch(name);
  return m==null?null:double.tryParse(m[1]!.replaceAll(',','.'));
}

/// Same signal: same frequency and same nature (real / exercise), else the
/// same normalized name for a signal without frequency.
String signalKey(SignalChoice s){
  final f=frequencyOfName(s.name)??s.frequencyMhz;
  return f!=null?'${(f*1000).round()}|${s.exercise}':'n|${normalizeSignalName(s.name)}';
}

/// Rank of the fixed head of the list (card « Signal recherché », 30 Oct
/// 2026): 121,5 real, 406 Cospas-Sarsat, 121,375 exercise; others after.
int _fixedRank(SignalChoice s){
  final f=s.frequencyMhz??frequencyOfName(s.name); if(f==null)return 3;
  if((f-121.5).abs()<0.0005&&!s.exercise)return 0;
  if(f>=406&&f<407&&!s.exercise)return 1;
  if((f-121.375).abs()<0.0005&&s.exercise)return 2;
  return 3;
}

/// The list shown in the bearing sheet, in a fixed order: 121,500 MHz real
/// beacon, 406 MHz Cospas-Sarsat, 121,375 MHz exercise beacon, then the other
/// signals (typed with « Autre… » [extra], then of the event most recent
/// first, then the visible defaults); « Autre… » is added by the sheet. One
/// line per frequency and nature, whatever the apostrophes of the name.
List<SignalChoice> signalMenu(Iterable<Bearing> bearings,List<SignalChoice> defaults,{List<SignalChoice> extra=const []}){
  final sorted=[...bearings]..sort((a,b)=>b.takenAt.compareTo(a.takenAt));
  final candidates=<SignalChoice>[];
  // The fixed beacons keep the name of the defaults (hidden ones included).
  for(final s in defaults){if(_fixedRank(s)<3)candidates.add(s);}
  candidates.addAll(extra);
  for(final b in sorted){
    if(b.search.isEmpty)continue;
    final d=defaults.where((s)=>normalizeSignalName(s.name)==normalizeSignalName(b.search)).firstOrNull;
    candidates.add(d??SignalChoice(label:b.search,exercise:b.exercise));
  }
  for(final s in defaults){if(!s.hidden)candidates.add(s);}
  final out=<SignalChoice>[]; final seen=<String>{};
  for(final s in candidates){if(s.name.isNotEmpty&&seen.add(signalKey(s)))out.add(s);}
  // Hidden by the administrator and never used: not shown.
  bool used(SignalChoice s)=>sorted.any((b)=>signalKey(SignalChoice(label:b.search,exercise:b.exercise))==signalKey(s))||extra.any((e)=>signalKey(e)==signalKey(s));
  final hiddenKeys={for(final d in defaults)if(d.hidden)signalKey(d)};
  out.removeWhere((s)=>hiddenKeys.contains(signalKey(s))&&!used(s));
  final head=[for(var r=0;r<3;r++)...out.where((s)=>_fixedRank(s)==r).take(1)];
  return [...head,...out.where((s)=>!head.contains(s))];
}

/// The entry of [menu] standing for the saved signal name [name] (same
/// frequency and nature, or same name with other apostrophes).
SignalChoice? signalFor(List<SignalChoice> menu,String name){
  final exact=menu.where((s)=>s.name==name).firstOrNull; if(exact!=null)return exact;
  final n=normalizeSignalName(name);
  return menu.where((s)=>normalizeSignalName(s.name)==n).firstOrNull;
}

/// « EXERCICE »: never mistake an exercise for a real distress.
class ExerciseBadge extends StatelessWidget {
  const ExerciseBadge({super.key});
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:1),
    decoration:BoxDecoration(color:const Color(0xFFFFE8CC),borderRadius:BorderRadius.circular(6),border:Border.all(color:const Color(0xFFE8710A))),
    child:const Text('EXERCICE',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:Color(0xFFB45309),letterSpacing:0.5)));
}
