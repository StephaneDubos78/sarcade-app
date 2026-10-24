import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/routes/route_models.dart';

Map<String,dynamic> wp(String id,double lat,double lon,{String leg='straight',List<List<double>>? geometry,String time='2026-10-10T06:00:00Z'})=>
  {'id':id,'route_id':'r1','name':id,'type':'pass','lat':lat,'lon':lon,'leg_mode':leg,'leg_geometry':geometry,'radius_m':50,'updated_at':time};

void main(){
  final route=RoutePlan({'id':'r1','name':'Approche','point_order':['b','a'],'created_by':'TEL-01'});
  final points=[Waypoint(wp('a',48.80,2.10)),Waypoint(wp('b',48.81,2.10)),Waypoint(wp('c',48.82,2.10,time:'2026-10-10T06:05:00Z'))];

  test('order of the route, unknown points last',(){
    expect(orderedWaypoints(route,points).map((w)=>w.id),['b','a','c']);
  });

  test('legs: computed path when present, straight otherwise',(){
    final a=Waypoint(wp('a',48.80,2.10));
    final b=Waypoint(wp('b',48.81,2.10,leg:'paths',geometry:[[48.80,2.10],[48.805,2.12],[48.81,2.10]]));
    expect(legPoints(a,b).length,3);
    final lengths=legLengths([a,b]);
    expect(lengths.first.leg,0);
    expect(lengths.last.cumulative,greaterThan(1112));
    expect(routeLine([a,b]).length,3);
  });

  test('assigned route changed only by its author and the PCO',(){
    final assigned=RoutePlan({'id':'r','created_by':'TEL-01','assigned_group_id':'g1'});
    expect(assigned.canEdit('TEL-02'),isFalse);
    expect(assigned.canEdit('TEL-01'),isTrue);
    expect(assigned.canEdit('PCO'),isTrue);
    expect(RoutePlan({'id':'r','created_by':'TEL-01'}).canEdit('TEL-02'),isTrue);
  });

  test('automatic passage within the approach radius of the next points',(){
    final ordered=[Waypoint(wp('a',48.80,2.10)),Waypoint(wp('b',48.81,2.10)),Waypoint(wp('c',48.82,2.10))];
    expect(reachedWaypoint(ordered,{},const LatLng(48.8002,2.1))?.id,'a');
    expect(reachedWaypoint(ordered,{'a'},const LatLng(48.8002,2.1)),isNull);
    expect(reachedWaypoint(ordered,{'a'},const LatLng(48.8101,2.1))?.id,'b');
    expect(reachedWaypoint(ordered,{},const LatLng(48.8201,2.1)),isNull,reason:'too far ahead in the route');
  });

  test('passages, names and types',(){
    final passages=[{'route_id':'r1','waypoint_id':'a','device_id':'TEL-01'},{'route_id':'r1','waypoint_id':'b','cancelled':true}];
    expect(passedWaypoints(passages,'r1'),{'a'});
    expect(nextWaypointType(0),'start');
    expect(nextWaypointType(2),'pass');
    expect(nextWaypointName(points),'P4');
  });

  test('itinerary from the server and straight line',(){
    final it=Itinerary.fromJson({'length_m':2600,'duration_s':180,'geometry':[[48.8,2.1],[48.81,2.1]],
      'maneuvers':[{'instruction':'Partez','length_m':1100,'begin_index':0}]});
    expect(it.lengthM,2600);
    expect(it.maneuvers.single.instruction,'Partez');
    final line=Itinerary.straightLine(const LatLng(48.8,2.1),const LatLng(48.81,2.1),'foot');
    expect(line.straight,isTrue);
    expect(line.durationS,closeTo(line.lengthM/1.2,0.01));
    expect(remainingM(it.geometry,const LatLng(48.8,2.1)),closeTo(1112,5));
  });

  test('formats',(){
    expect(formatDistance(350),'350 m');
    expect(formatDistance(1234),'1,2 km');
    expect(formatDuration(720),'12 min');
    expect(formatDuration(3900),'1 h 05');
  });
}
