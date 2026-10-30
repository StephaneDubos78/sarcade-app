/// Operators and APRS stations on the map, interface V2 (mock-up validated
/// on 27 Oct 2026, « Inspirations d'autres applications » 1, 2, 4, 5, 8,
/// 9, 10): freshness, source, real APRS symbols, groups, favourites,
/// proximity.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/position.dart';
import 'drawing/geometry.dart' as geo;

/// Age of a position: normal under 2 min, ageing until 10 min, then stale
/// (grey, crossed out, with the exact time). Thresholds per event.
enum Freshness { fresh, ageing, stale }

Freshness freshness(DateTime time,DateTime now,{int ageingMin=2,int staleMin=10}){
  final age=now.difference(time);
  if(age.inSeconds<ageingMin*60)return Freshness.fresh;
  if(age.inSeconds<staleMin*60)return Freshness.ageing;
  return Freshness.stale;
}

/// Platform sent by the application (« android ») as shown (« Android »).
String platformLabel(String p)=>switch(p.toLowerCase()){
  'android'=>'Android','ios'=>'iPhone','web'=>'Web','windows'=>'Windows','linux'=>'Linux','macos'=>'Mac',_=>p};

/// « 12 s », « 6 min », « 2 h », « 3 j ».
/// Number and unit joined by a no-break space: « 27 min » never cut in two
/// (revue d'ergonomie n° 43).
String ageLabel(DateTime time,DateTime now){
  final d=now.difference(time);
  if(d.inSeconds<60)return '${d.inSeconds<0?0:d.inSeconds}\u00A0s';
  if(d.inMinutes<60)return '${d.inMinutes}\u00A0min';
  if(d.inHours<48)return '${d.inHours}\u00A0h';
  return '${d.inDays}\u00A0j';
}

/// Way the position came: the SARCADE app, APRS by radio (Gateway, works
/// without Internet) or APRS-IS (Internet).
enum PositionSource { app, aprsRadio, aprsInternet }

PositionSource sourceOf(SarcadePosition p)=>!p.isAprs?PositionSource.app:p.aprsVia=='rf'?PositionSource.aprsRadio:PositionSource.aprsInternet;

/// « Sans Internet seulement »: what would still arrive in an Internet
/// outage (APRS by radio).
bool worksWithoutInternet(SarcadePosition p)=>sourceOf(p)==PositionSource.aprsRadio;

/// APRS symbol → icon, and the overlay character of the alternate table
/// (« L& » = LoRa iGate: « L » drawn over the iGate symbol).
({IconData icon,String? overlay,String kind}) aprsSymbol(String? symbol){
  if(symbol==null||symbol.length<2)return (icon:Icons.settings_input_antenna,overlay:null,kind:'station');
  final table=symbol[0], code=symbol[1];
  final overlay=(table=='/'||table=='\\')?null:table;
  const map=<String,(IconData,String)>{
    '>':(Icons.directions_car,'car'),'k':(Icons.local_shipping,'truck'),'u':(Icons.local_shipping,'truck'),'v':(Icons.airport_shuttle,'van'),
    'j':(Icons.directions_car,'jeep'),'<':(Icons.two_wheeler,'motorcycle'),'b':(Icons.pedal_bike,'bike'),'[':(Icons.directions_walk,'person'),
    'a':(Icons.emergency,'ambulance'),'f':(Icons.fire_truck,'fire'),'s':(Icons.directions_boat,'boat'),'^':(Icons.flight,'aircraft'),
    "'":(Icons.flight,'aircraft'),'X':(Icons.airplanemode_active,'helicopter'),'O':(Icons.air,'balloon'),'-':(Icons.home,'house'),
    '_':(Icons.thermostat,'weather'),'#':(Icons.repeat,'digipeater'),'&':(Icons.router,'igate'),'r':(Icons.cell_tower,'repeater'),
    'y':(Icons.home,'house'),'R':(Icons.rv_hookup,'rv'),'U':(Icons.directions_bus,'bus'),'=':(Icons.train,'train'),
  };
  final hit=map[code];
  if(hit==null)return (icon:Icons.settings_input_antenna,overlay:overlay,kind:'station');
  return (icon:hit.$1,overlay:overlay,kind:hit.$2);
}

/// Favourites first, then by name.
List<SarcadePosition> sortStations(Iterable<SarcadePosition> list,Set<String> favourites)=>list.toList()
  ..sort((a,b){
    final fa=favourites.contains(a.deviceId)?0:1, fb=favourites.contains(b.deviceId)?0:1;
    return fa!=fb?fa-fb:a.label.compareTo(b.label);
  });

/// « À proximité » (Tesla): items nearest to [from], with distance and
/// azimuth.
class Nearby<T> {
  final T item; final double distanceM, azimuthDeg;
  const Nearby(this.item,this.distanceM,this.azimuthDeg);
}
List<Nearby<T>> nearest<T>(LatLng from,Iterable<T> items,LatLng Function(T) at,{int limit=30}){
  final out=[for(final i in items)Nearby(i,geo.distanceM(from,at(i)),geo.bearingDeg(from,at(i)))]
    ..sort((a,b)=>a.distanceM.compareTo(b.distanceM));
  return out.take(limit).toList();
}

/// Groups of markers closer than [radiusPx] on screen (Tesla « 11 »);
/// [screen] gives the screen offset of a position.
List<List<T>> clusterOnScreen<T>(List<T> items,Offset Function(T) screen,{double radiusPx=44}){
  final groups=<List<T>>[]; final centres=<Offset>[];
  for(final i in items){
    final o=screen(i);
    var placed=false;
    for(var g=0;g<groups.length;g++){
      if((centres[g]-o).distance<radiusPx){groups[g].add(i);placed=true;break;}
    }
    if(!placed){groups.add([i]);centres.add(o);}
  }
  return groups;
}

/// Trace of a station over the last [hours].
List<SarcadePosition> traceWithin(List<SarcadePosition> history,DateTime now,int hours)=>
  history.where((p)=>now.difference(p.time).inMinutes<=hours*60).toList()..sort((a,b)=>a.time.compareTo(b.time));

/// Sections of the list (« Liste des opérateurs triée par fraîcheur »,
/// 28 Oct 2026): active under 10 min, without news up to the « old »
/// threshold (2 h by default, PCO setting later), then old (folded, and
/// hidden on the map).
enum Section{active,silent,old}
Section sectionOf(DateTime time,DateTime now,{int activeMin=10,int oldMin=120}){
  final age=now.difference(time);
  if(age<Duration(minutes:activeMin))return Section.active;
  if(age<Duration(minutes:oldMin))return Section.silent;
  return Section.old;
}

/// Favourites kept on the device, « a|b|c ».
Set<String> parseFavourites(String? v)=>v==null||v.isEmpty?<String>{}:v.split('|').where((s)=>s.isNotEmpty).toSet();
String encodeFavourites(Set<String> f)=>(f.toList()..sort()).join('|');

/// State of the link with the server (« Pastille des liaisons simplifiée »):
/// direct (everything at once), slowed (no realtime, updates about every
/// minute), cut (offline, sent later).
enum ServerLink{direct,slowed,cut}
ServerLink serverLink({required bool? syncOk,required bool realtime})=>
  syncOk==false?ServerLink.cut:realtime?ServerLink.direct:ServerLink.slowed;
