import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/import_formats.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

const _gpx='''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="48.7712" lon="2.0345"><name>PC avancé</name></wpt>
  <wpt lat="bad" lon="2.0"><name>Invalide</name></wpt>
  <rte><name>Itinéraire</name><rtept lat="48.70" lon="2.00"/><rtept lat="48.71" lon="2.01"/></rte>
  <trk><name>Trace équipe 1</name>
    <trkseg><trkpt lat="48.70" lon="2.00"/><trkpt lat="48.705" lon="2.005"/><trkpt lat="48.71" lon="2.01"/></trkseg>
    <trkseg><trkpt lat="48.72" lon="2.02"/><trkpt lat="48.73" lon="2.03"/></trkseg>
  </trk>
</gpx>''';

const _kml='''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
  <Placemark><name>Relais Septeuil</name><Point><coordinates>1.6833,48.8917,0</coordinates></Point></Placemark>
  <Placemark><name>Secteur Nord</name>
    <Style><LineStyle><color>ff0000ff</color></LineStyle></Style>
    <Polygon><outerBoundaryIs><LinearRing><coordinates>
      2.00,48.70,0 2.01,48.70,0 2.01,48.71,0 2.00,48.71,0 2.00,48.70,0
    </coordinates></LinearRing></outerBoundaryIs></Polygon>
  </Placemark>
  <Placemark><name>Axe</name><MultiGeometry>
    <LineString><coordinates>2.0,48.7 2.1,48.8</coordinates></LineString>
    <Point><coordinates>2.05,48.75</coordinates></Point>
  </MultiGeometry></Placemark>
  <Placemark><name>Vide</name></Placemark>
</Document></kml>''';

void main(){
  test('GPX: waypoints, routes and each track segment',(){
    final r=parseGpx(_gpx);
    expect(r.shapes.map((s)=>s.kind),[FeatureKind.point,FeatureKind.line,FeatureKind.line,FeatureKind.line]);
    expect(r.shapes.first.label,'PC avancé');
    expect(r.shapes.first.points.single,const LatLng(48.7712,2.0345));
    expect(r.shapes[2].label,'Trace équipe 1 (1)');
    expect(r.shapes[2].points.length,3);
    expect(r.skipped,1);
  });

  test('KML: points, polygon outer ring without closing point, multigeometry, colours',(){
    final r=parseKml(_kml);
    expect(r.shapes.length,4);
    final zone=r.shapes[1];
    expect(zone.kind,FeatureKind.zone);
    expect(zone.points.length,4);
    expect(zone.points.first,const LatLng(48.70,2.00));
    expect(zone.color,0xFFFF0000);
    // MultiGeometry gives one object per geometry, with the placemark name.
    expect(r.shapes.sublist(2).map((s)=>s.kind).toSet(),{FeatureKind.line,FeatureKind.point});
    expect(r.shapes.sublist(2).every((s)=>s.label=='Axe'),isTrue);
    expect(r.skipped,1);
  });

  test('KML colours aabbggrr become opaque ARGB',(){
    expect(kmlColor('ff00ff00'),0xFF00FF00);
    expect(kmlColor('7f0000ff'),0xFFFF0000);
    expect(kmlColor('rouge'),isNull);
  });

  test('KMZ: reads doc.kml from the archive',(){
    final archive=Archive()..addFile(ArchiveFile.string('doc.kml',_kml));
    final bytes=ZipEncoder().encode(archive);
    final r=parseMapFile('secteurs.kmz',bytes);
    expect(r.shapes.length,4);
  });

  test('GeoJSON: geometries in lon/lat order, names and stroke colours',(){
    final g=jsonEncode({'type':'FeatureCollection','features':[
      {'type':'Feature','properties':{'name':'Point haut','stroke':'#1e88e5'},'geometry':{'type':'Point','coordinates':[1.68,48.89]}},
      {'type':'Feature','properties':{'title':'Zone'},'geometry':{'type':'Polygon','coordinates':[[[2.0,48.7],[2.01,48.7],[2.01,48.71],[2.0,48.7]]]}},
      {'type':'Feature','properties':{},'geometry':{'type':'MultiLineString','coordinates':[[[2.0,48.7],[2.1,48.8]],[[2.2,48.9],[2.3,49.0]]]}},
      {'type':'Feature','properties':{},'geometry':null},
    ]});
    final r=parseGeoJson(g);
    expect(r.shapes.length,4);
    expect(r.shapes.first.points.single,const LatLng(48.89,1.68));
    expect(r.shapes.first.color,0xFF1E88E5);
    expect(r.shapes[1].kind,FeatureKind.zone);
    expect(r.shapes[1].points.length,3);
    expect(r.shapes[1].label,'Zone');
    expect(r.skipped,1);
  });

  test('a SARCADE GeoJSON export imports back with its kinds',(){
    final now=DateTime.utc(2026,10,7);
    MapFeature f(FeatureKind k,List<LatLng> pts,{double? r})=>MapFeature(id:k.name,eventId:'e',kind:k,points:pts,radiusM:r,color:0xFF43A047,strokeWidth:4,label:k.label,updatedAt:now);
    final exported=jsonEncode(featureCollection([
      f(FeatureKind.circle,const [LatLng(48.7,2.0)],r:250),
      f(FeatureKind.arrow,const [LatLng(48.7,2.0),LatLng(48.8,2.1)]),
      f(FeatureKind.text,const [LatLng(48.7,2.0)]),
      f(FeatureKind.measure,const [LatLng(48.7,2.0),LatLng(48.8,2.1)]),
      f(FeatureKind.rectangle,const [LatLng(48.7,2.0),LatLng(48.8,2.1)]),
    ]));
    final r=parseMapFile('objets.geojson',utf8.encode(exported));
    expect(r.shapes.map((s)=>s.kind),[FeatureKind.circle,FeatureKind.arrow,FeatureKind.text,FeatureKind.measure,FeatureKind.zone]);
    expect(r.shapes.first.radiusM,250);
    expect(r.shapes.first.color,0xFF43A047);
    expect(r.shapes[2].label,'Texte');
  });

  test('long GPS tracks are thinned under the server limit, keeping both ends',(){
    final pts=[for(var i=0;i<12000;i++)'<trkpt lat="${48+i*1e-5}" lon="2.0"/>'].join();
    final r=parseGpx('<gpx><trk><trkseg>$pts</trkseg></trk></gpx>');
    final line=r.shapes.single.points;
    expect(line.length,lessThanOrEqualTo(maxPointsPerShape));
    expect(line.first.latitude,48);
    expect(line.last.latitude,closeTo(48+11999e-5,1e-9));
  });

  test('unsupported or empty files give a French error',(){
    expect(()=>parseMapFile('carte.shp',[1,2,3]),throwsA(isA<ImportFormatException>()));
    expect(()=>parseGpx('<gpx></gpx>'),throwsA(isA<ImportFormatException>()));
    expect(()=>parseKml('pas du xml'),throwsA(isA<ImportFormatException>()));
    expect(()=>parseGeoJson('{'),throwsA(isA<ImportFormatException>()));
  });

  test('an import is one undo step and every object is synchronised',(){
    final created=<String>[];
    final c=DrawingController(eventId:'e',actorId:'PCO',onChanged:(f,{required isNew}){if(isNew)created.add(f.id);});
    final r=parseKml(_kml);
    final features=c.importShapes(r.shapes);
    expect(features.length,4);
    expect(created.length,4);
    expect(features[1].color,0xFFFF0000);
    expect(features[0].color,drawingPalette.first);
    c.undo();
    expect(c.features,isEmpty);
  });
}
