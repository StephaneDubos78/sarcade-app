import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/navigation/road_graph.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

/// Package built by sarcade-server from demo/osm/sample.osm (tests of the
/// server compute the same itineraries with a reference Dijkstra).
RoadGraph sample()=>RoadGraph.parse(File('test/fixtures/sample-graph.srg.gz').readAsBytesSync());

double duration(RoadGraph g,List<int> path,String mode){
  final speeds=g.speedsKmh[mode]!;
  return path.fold(0.0,(t,code){final e=code>>1;return t+g.eLength[e]/(speeds[g.eClass[e]]/3.6);});
}

List<int> vertices(RoadGraph g,int start,List<int> path){
  final out=[start]; var v=start;
  for(final code in path){final e=code>>1;v=(code&1)==0?g.eTo[e]:g.eFrom[e];out.add(v);}
  return out;
}

void main(){
  test('SRG1 package from the server',(){
    final g=sample();
    expect(g.vertexCount,5);
    expect(g.edgeCount,6);
    expect(g.names,contains('D30'));
    expect(g.attribution,startsWith('© OpenStreetMap'));
    expect(g.vertex(3).latitude,closeTo(48.81,1e-6));
  });

  test('same itineraries as the reference of the server',(){
    final g=sample();
    final p32=g.shortestPath(3,2,'car')!;
    expect(vertices(g,3,p32),[3,1,2],reason:'D30 is one-way');
    expect(duration(g,p32,'car'),closeTo(167.78,0.1));
    final p23=g.shortestPath(2,3,'car')!;
    expect(vertices(g,2,p23),[2,3]);
    expect(duration(g,p23,'car'),closeTo(50.04,0.1));
    expect(g.shortestPath(0,4,'car'),isNull,reason:'forest track closed to cars');
    expect(vertices(g,0,g.shortestPath(0,4,'offroad')!),[0,4]);
    final foot=g.shortestPath(4,3,'foot')!;
    expect(vertices(g,4,foot),[4,3],reason:'the footpath');
    expect(duration(g,foot,'foot'),closeTo(1171.65,0.5));
  });

  test('closed road avoided, roads meeting it stay open',(){
    final g=sample();
    final d30=[const LatLng(48.80,2.12),const LatLng(48.81,2.12)];
    final blocked=g.blockedEdges([d30]);
    expect(blocked.length,1);
    final path=g.shortestPath(2,3,'car',blocked:blocked)!;
    expect(vertices(g,2,path),[2,1,3]);
  });

  test('itinerary with approach, geometry and simple instructions',(){
    S.setLanguage('fr');
    final g=sample();
    final it=g.route(const LatLng(48.7999,2.1001),const LatLng(48.8101,2.1199),'car',t:S.t)!;
    expect(it.onDevice,isTrue);
    expect(it.geometry.first.latitude,closeTo(48.7999,1e-9));
    expect(it.lengthM,greaterThan(2000));
    expect(it.maneuvers.first.instruction,'Partir sur Rue A');
    expect(it.maneuvers.last.instruction,'Arrivée à destination');
    expect(it.maneuvers.map((m)=>m.instruction).any((i)=>i.contains('Rue B')),isTrue);
    expect(g.route(const LatLng(48.80,2.10),const LatLng(48.81,2.10),'car'),isNotNull,
      reason:'nearest vertex reachable by car is used');
  });
}
