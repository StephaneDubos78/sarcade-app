/// Traces of every operator (card « Carte, traces de tous les opérateurs »,
/// validated on 30 Oct 2026, 1 h 26): layer « Traces » of the « Affichage »
/// tab with « Toutes les traces » and its opacity; window 30 min, 1 h,
/// 2 h (default), 6 h or the whole event; each trace in the colour of the
/// operator, paler with age; a touch on an operator pins his trace (several
/// at once), a second touch removes it; APRS stations as a separate option.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../models/position.dart';
import '../bearings/bearing_models.dart' show operatorColor;

/// Windows offered, in minutes; 0 = the whole event.
const traceWindows=[30,60,120,360,0];
const defaultTraceWindow=120;

String traceWindowLabel(int min)=>min==0?S.t('traces.event'):min<60?'$min min':'${min~/60} h';

int traceWindowFrom(String? stored){final v=int.tryParse(stored??'');return v!=null&&traceWindows.contains(v)?v:defaultTraceWindow;}

/// Opacity of a point of the trace by its age: 1 when fresh, 0.2 at the
/// end of the window (the whole event: over 6 h).
double traceAlpha(Duration age,int windowMin){
  final span=(windowMin==0?360:windowMin)*60.0;
  final r=(age.inSeconds/span).clamp(0.0,1.0);
  return 1-0.8*r;
}

/// Positions of [history] within the window, oldest first, split where the
/// station was silent more than 5 min.
List<List<SarcadePosition>> traceSegmentsOf(List<SarcadePosition> history,DateTime now,int windowMin){
  final pts=history.where((p)=>windowMin==0||now.difference(p.time.toUtc()).inMinutes<=windowMin).toList()..sort((a,b)=>a.time.compareTo(b.time));
  final out=<List<SarcadePosition>>[]; var cur=<SarcadePosition>[];
  for(final p in pts){
    if(cur.isNotEmpty&&p.time.toUtc().difference(cur.last.time.toUtc())>const Duration(minutes:5)){if(cur.length>1)out.add(cur);cur=[];}
    cur.add(p);
  }
  if(cur.length>1)out.add(cur);
  return out;
}

/// Histories of the stations, loaded on demand and kept up to date by the
/// live positions.
class TracesStore {
  final Future<List<SarcadePosition>> Function(String deviceId) load;
  final VoidCallback onChanged;
  TracesStore({required this.load,required this.onChanged});
  final Map<String,List<SarcadePosition>> _history={};
  final Map<String,DateTime> _loadedAt={};
  final Set<String> pinned={};

  /// Pins or unpins the trace of [id]; true when pinned.
  bool togglePin(String id){
    if(!pinned.remove(id)){pinned.add(id);unawaited(ensure([id]));return true;}
    onChanged();
    return false;
  }

  /// Loads the histories not read in the last 2 minutes.
  Future<void> ensure(Iterable<String> ids) async {
    final now=DateTime.now();
    final todo=[for(final id in ids)if(_loadedAt[id]==null||now.difference(_loadedAt[id]!)>const Duration(minutes:2))id];
    for(final id in todo){
      _loadedAt[id]=now;
      try{_history[id]=await load(id);}catch(_){/* retried after 2 min */}
    }
    if(todo.isNotEmpty)onChanged();
  }

  void add(SarcadePosition p){final h=_history[p.deviceId];if(h!=null&&(h.isEmpty||h.last.id!=p.id))h.add(p);}

  /// Polylines of [ids]: one short line per pair of points, paler with age.
  List<Polyline> polylines(Iterable<String> ids,{required int windowMin,DateTime? now}){
    final at=(now??DateTime.now()).toUtc();
    final out=<Polyline>[];
    for(final id in ids){
      final colour=Color(operatorColor(id));
      for(final seg in traceSegmentsOf(_history[id]??const [],at,windowMin)){
        for(var i=1;i<seg.length;i++){
          out.add(Polyline(points:[LatLng(seg[i-1].lat,seg[i-1].lon),LatLng(seg[i].lat,seg[i].lon)],strokeWidth:3.5,
            color:colour.withValues(alpha:traceAlpha(at.difference(seg[i].time.toUtc()),windowMin))));
        }
      }
    }
    return out;
  }
}

/// « Durée des traces » and its choices (card « Fond et affichage, durée
/// des traces ambiguë », 30 Oct 2026, 17 h 45): one window for every trace
/// (operators, APRS stations, pinned traces), titled so that it does not
/// read as an APRS option.
Widget traceWindowChips(int current,ValueChanged<int> onPick)=>Padding(padding:const EdgeInsets.fromLTRB(16,4,8,4),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
    Builder(builder:(c)=>Text(S.t('traces.window'),style:Theme.of(c).textTheme.bodyMedium)),
    const SizedBox(height:4),
    Wrap(spacing:6,runSpacing:4,children:[for(final w in traceWindows)ChoiceChip(key:ValueKey('trace-window-$w'),visualDensity:VisualDensity.compact,
      label:Text(traceWindowLabel(w)),selected:current==w,onSelected:(_)=>onPick(w))]),
  ]));

/// « Traces APRS » on by default (card of 30 Oct 2026, 16 h 13): stored
/// « 0 » only when turned off; the fixed stations never have a trace.
bool aprsTracesFrom(String? stored)=>stored!='0';
