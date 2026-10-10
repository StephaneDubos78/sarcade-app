/// Routes with waypoints, road closures and shared itineraries (notes
/// « Route avec points de passage » and « Navigation »). Pure code, testable
/// without Flutter. Objects are kept as JSON maps, the format of the server.
library;

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../../models/comm_group.dart' show isPco;
import '../map/drawing/geometry.dart';

const routeObjectTypes={'route','route_waypoint','route_passage','road_closure','itinerary'};
const waypointTypes=['start','pass','checkpoint','supply','finish'];
const defaultRadiusM=50.0;

DateTime _time(Object? v)=>DateTime.tryParse('$v')??DateTime.fromMillisecondsSinceEpoch(0,isUtc:true);
List<String> _strings(Object? v)=>v is List?v.whereType<String>().toList():<String>[];
List<LatLng> _line(Object? v){
  if(v is! List)return const [];
  return [for(final p in v) if(p is List&&p.length==2&&p[0] is num&&p[1] is num) LatLng((p[0] as num).toDouble(),(p[1] as num).toDouble())];
}
List<List<double>> lineJson(List<LatLng> pts)=>[for(final p in pts)[p.latitude,p.longitude]];

class RoutePlan {
  final Map<String,dynamic> json;
  const RoutePlan(this.json);
  String get id=>json['id'] as String;
  String get name=>(json['name'] as String?)??'';
  int get color=>(json['color'] as num?)?.toInt()??0xFF1E88E5;
  String get profile=>(json['profile'] as String?)??'foot';
  String get defaultLegMode=>(json['default_leg_mode'] as String?)??'straight';
  String get status=>(json['status'] as String?)??'draft';
  String get createdBy=>(json['created_by'] as String?)??'';
  List<String> get pointOrder=>_strings(json['point_order']);
  String? get assignedTeamId=>json['assigned_team_id'] as String?;
  String? get assignedGroupId=>json['assigned_group_id'] as String?;
  bool get assigned=>(assignedTeamId?.isNotEmpty??false)||(assignedGroupId?.isNotEmpty??false);
  /// An assigned route is changed only by its author and the PCO (server rule).
  bool canEdit(String actorId)=>!assigned||isPco(actorId)||actorId==createdBy;
}

class Waypoint {
  final Map<String,dynamic> json;
  const Waypoint(this.json);
  String get id=>json['id'] as String;
  String get routeId=>(json['route_id'] as String?)??'';
  String get name=>(json['name'] as String?)??'';
  String get type=>(json['type'] as String?)??'pass';
  LatLng get point=>LatLng((json['lat'] as num).toDouble(),(json['lon'] as num).toDouble());
  String get comment=>(json['comment'] as String?)??'';
  double get radiusM=>(json['radius_m'] as num?)?.toDouble()??defaultRadiusM;
  String get legMode=>(json['leg_mode'] as String?)??'straight';
  List<LatLng> get legGeometry=>_line(json['leg_geometry']);
  bool get legNeedsRouting=>json['leg_needs_routing']==true;
  DateTime get updatedAt=>_time(json['updated_at']);
}

/// Waypoints in the order of the route; points missing from the order (added
/// offline by someone else) come last, by time.
List<Waypoint> orderedWaypoints(RoutePlan route,Iterable<Waypoint> all){
  final mine={for(final w in all) if(w.routeId==route.id) w.id:w};
  final order=[for(final id in route.pointOrder) if(mine.containsKey(id)) id];
  final rest=mine.keys.where((id)=>!order.contains(id)).toList()..sort((a,b)=>mine[a]!.updatedAt.compareTo(mine[b]!.updatedAt));
  return [for(final id in [...order,...rest]) mine[id]!];
}

/// Points drawn for the leg arriving at [to]: the computed path when it
/// exists, else a straight line.
List<LatLng> legPoints(Waypoint from,Waypoint to){
  final g=to.legMode=='paths'?to.legGeometry:const <LatLng>[];
  return g.length>=2?g:[from.point,to.point];
}

/// Whole line of a route, leg after leg.
List<LatLng> routeLine(List<Waypoint> ordered){
  final out=<LatLng>[];
  for(var i=1;i<ordered.length;i++){
    final leg=legPoints(ordered[i-1],ordered[i]);
    out.addAll(out.isEmpty?leg:leg.skip(1));
  }
  if(out.isEmpty&&ordered.isNotEmpty)out.add(ordered.first.point);
  return out;
}

/// Length of each leg and cumulated, in metres (first point: 0).
List<({double leg,double cumulative})> legLengths(List<Waypoint> ordered){
  final out=<({double leg,double cumulative})>[];
  var total=0.0;
  for(var i=0;i<ordered.length;i++){
    final leg=i==0?0.0:pathLength(legPoints(ordered[i-1],ordered[i]));
    total+=leg;
    out.add((leg:leg,cumulative:total));
  }
  return out;
}

/// Default type of a new point: start first, then passage.
String nextWaypointType(int existing)=>existing==0?'start':'pass';

/// Default name: P1, P2…
String nextWaypointName(Iterable<Waypoint> existing){
  var n=existing.length+1;
  final names=existing.map((w)=>w.name).toSet();
  while(names.contains('P$n')){n++;}
  return 'P$n';
}

/// Passages recorded at the waypoints (cancelled ones ignored).
Set<String> passedWaypoints(Iterable<Map<String,dynamic>> passages,String routeId,{String? deviceId}){
  return {for(final p in passages)
    if(p['route_id']==routeId&&p['cancelled']!=true&&(deviceId==null||p['device_id']==deviceId)) p['waypoint_id'] as String};
}

/// Waypoint reached by a position (within its approach radius), not yet
/// passed: gives an automatic passage. Only the next points are considered,
/// so that crossing the route elsewhere does not validate a distant point.
Waypoint? reachedWaypoint(List<Waypoint> ordered,Set<String> passed,LatLng position){
  var nextIndex=0;
  for(var i=0;i<ordered.length;i++){if(passed.contains(ordered[i].id))nextIndex=i+1;}
  for(var i=nextIndex;i<ordered.length&&i<nextIndex+2;i++){
    final w=ordered[i];
    if(!passed.contains(w.id)&&distanceM(position,w.point)<=w.radiusM)return w;
  }
  return null;
}

/// Road closed by the PCO.
class RoadClosure {
  final Map<String,dynamic> json;
  const RoadClosure(this.json);
  String get id=>json['id'] as String;
  String get label=>(json['label'] as String?)??'';
  List<LatLng> get points=>_line(json['points']);
  bool get active=>json['active']!=false;
}

/// Itinerary computed by the server or a straight line.
class Itinerary {
  final List<LatLng> geometry; final double lengthM; final double durationS;
  final List<({String instruction,double lengthM,int beginIndex})> maneuvers;
  final bool straight;
  /// Computed on the device from the road graph (server unreachable).
  final bool onDevice;
  const Itinerary({required this.geometry,required this.lengthM,required this.durationS,this.maneuvers=const [],this.straight=false,this.onDevice=false});

  factory Itinerary.fromJson(Map<String,dynamic> j)=>Itinerary(
    geometry:_line(j['geometry']),
    lengthM:(j['length_m'] as num?)?.toDouble()??0,
    durationS:(j['duration_s'] as num?)?.toDouble()??0,
    maneuvers:[for(final m in (j['maneuvers'] as List?)??const []) if(m is Map)(
      instruction:'${m['instruction']??''}',lengthM:((m['length_m']??m['length']) as num?)?.toDouble()??0,
      beginIndex:(m['begin_index'] as num?)?.toInt()??0)],
  );

  /// Straight line when the engine is unreachable: distance and bearing,
  /// duration at walking or driving pace.
  factory Itinerary.straightLine(LatLng from,LatLng to,String mode){
    final d=distanceM(from,to);
    final speed=mode=='foot'?1.2:(mode=='offroad'?6.0:11.0);
    return Itinerary(geometry:[from,to],lengthM:d,durationS:d/speed,straight:true);
  }
}

/// Variants of the server itinerary (« alternatives », at most two).
List<Itinerary> alternativesFromJson(Map<String,dynamic> j)=>[
  for(final a in (j['alternatives'] as List?)??const []) if(a is Map) Itinerary.fromJson(Map<String,dynamic>.from(a))];

/// Share of [candidate]'s length lying within [withinM] of [reference],
/// sampled every [stepM] (same rule as the server).
double sharedShare(List<LatLng> candidate,List<LatLng> reference,{double withinM=30,double stepM=25}){
  if(candidate.length<2||reference.length<2)return 0;
  final lat0=candidate.first.latitude*math.pi/180;
  final kx=111320*math.cos(lat0), ky=110540.0;
  final ref=[for(final p in reference)(p.longitude*kx,p.latitude*ky)];
  double toRef(double x,double y){
    var best=double.infinity;
    for(var i=1;i<ref.length;i++){
      final (ax,ay)=ref[i-1]; final (bx,by)=ref[i];
      final dx=bx-ax, dy=by-ay; final len2=dx*dx+dy*dy;
      var t=len2==0?0.0:((x-ax)*dx+(y-ay)*dy)/len2;
      t=t.clamp(0.0,1.0);
      final ex=ax+t*dx-x, ey=ay+t*dy-y;
      final d=math.sqrt(ex*ex+ey*ey);
      if(d<best)best=d;
    }
    return best;
  }
  var total=0.0, near=0.0;
  for(var i=1;i<candidate.length;i++){
    final ax=candidate[i-1].longitude*kx, ay=candidate[i-1].latitude*ky;
    final bx=candidate[i].longitude*kx, by=candidate[i].latitude*ky;
    final seg=math.sqrt((bx-ax)*(bx-ax)+(by-ay)*(by-ay));
    final n=math.max(1,(seg/stepM).floor());
    for(var k=0;k<n;k++){
      final t=(k+0.5)/n;
      total+=seg/n;
      if(toRef(ax+(bx-ax)*t,ay+(by-ay)*t)<=withinM)near+=seg/n;
    }
  }
  return total==0?0:near/total;
}

/// At most [max] variants, without those that are nearly the same road as
/// the main itinerary or a variant already kept, nor those much longer.
List<Itinerary> distinctAlternatives(Itinerary main,List<Itinerary> candidates,{int max=2,double sameShare=0.85,double maxRatio=1.6}){
  final kept=<Itinerary>[];
  for(final c in candidates){
    if(c.geometry.length<2)continue;
    if(main.durationS>0&&c.durationS>main.durationS*maxRatio)continue;
    if([main,...kept].any((o)=>sharedShare(c.geometry,o.geometry,withinM:30)>=sameShare))continue;
    kept.add(c);
    if(kept.length==max)break;
  }
  return kept;
}

/// Remaining distance along the itinerary from the closest point of the line.
double remainingM(List<LatLng> geometry,LatLng position){
  if(geometry.isEmpty)return 0;
  var best=0; var bestD=double.infinity;
  for(var i=0;i<geometry.length;i++){final d=distanceM(position,geometry[i]);if(d<bestD){bestD=d;best=i;}}
  return bestD+pathLength(geometry.sublist(best));
}

/// Arrived when closer than this to the destination.
const arrivalRadiusM=30.0;

/// « 1,2 km », « 350 m ».
String formatDistance(double m,{String decimal=','}){
  if(m>=1000)return '${(m/1000).toStringAsFixed(m>=10000?0:1).replaceAll('.',decimal)} km';
  return '${m.round()} m';
}

/// « 1 h 05 », « 12 min ».
String formatDuration(double s){
  final min=(s/60).round();
  if(min<60)return '$min min';
  return '${min~/60} h ${(min%60).toString().padLeft(2,'0')}';
}
