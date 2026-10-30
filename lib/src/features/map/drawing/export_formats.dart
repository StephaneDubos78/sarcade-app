/// Export of drawn objects as GeoJSON, KML or GPX (card « Sélection, bouton
/// « Exporter » des objets sélectionnés », 30 Oct 2026, 17 h 41): reuse in
/// uMap, QGIS, Google My Maps, a GPS, another event or server.
library;

import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'map_feature.dart';

enum ExportFormat { geojson, kml, gpx }

extension ExportFormatInfo on ExportFormat {
  String get extension=>switch(this){ExportFormat.geojson=>'geojson',ExportFormat.kml=>'kml',ExportFormat.gpx=>'gpx'};
  String get mimeType=>switch(this){
    ExportFormat.geojson=>'application/geo+json',
    ExportFormat.kml=>'application/vnd.google-earth.kml+xml',
    ExportFormat.gpx=>'application/gpx+xml'};
  String get label=>switch(this){ExportFormat.geojson=>'GeoJSON',ExportFormat.kml=>'KML',ExportFormat.gpx=>'GPX'};
}

String _esc(String s)=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
String _n(double v)=>v.toStringAsFixed(7);

/// Outline of a circle (36 points), for KML and GPX which have no circle.
List<LatLng> circleOutline(LatLng centre,double radiusM,{int steps=36}){
  const d=Distance();
  return [for(var i=0;i<steps;i++)d.offset(centre,radiusM,i*360/steps)];
}

String _name(MapFeature f)=>f.label.isNotEmpty?f.label:f.kind.label;

List<LatLng> _outline(MapFeature f)=>f.kind==FeatureKind.circle&&f.radiusM!=null?circleOutline(f.points.first,f.radiusM!):f.ring;

/// KML 2.2, colours aabbggrr.
String featuresToKml(Iterable<MapFeature> features,{String name='SARCADE'}){
  String colour(MapFeature f){
    final c=f.color&0xFFFFFF; final r=(c>>16)&0xFF, g=(c>>8)&0xFF, b=c&0xFF;
    String h(int v)=>v.toRadixString(16).padLeft(2,'0');
    return 'ff${h(b)}${h(g)}${h(r)}';
  }
  String coords(Iterable<LatLng> pts)=>pts.map((p)=>'${_n(p.longitude)},${_n(p.latitude)},0').join(' ');
  final b=StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>${_esc(name)}</name>\n');
  for(final f in features){
    b.write('<Placemark><name>${_esc(_name(f))}</name><Style><LineStyle><color>${colour(f)}</color><width>${f.strokeWidth}</width></LineStyle>'
      '<PolyStyle><color>40${colour(f).substring(2)}</color></PolyStyle></Style>');
    if(f.kind==FeatureKind.point||f.kind==FeatureKind.text){
      b.write('<Point><coordinates>${coords([f.points.first])}</coordinates></Point>');
    }else if(f.isClosed){
      final ring=_outline(f);
      b.write('<Polygon><outerBoundaryIs><LinearRing><coordinates>${coords([...ring,ring.first])}</coordinates></LinearRing></outerBoundaryIs></Polygon>');
    }else{
      b.write('<LineString><coordinates>${coords(f.points)}</coordinates></LineString>');
    }
    b.write('</Placemark>\n');
  }
  b.write('</Document></kml>\n');
  return b.toString();
}

/// GPX 1.1: points as waypoints, lines as tracks, closed shapes as closed tracks.
String featuresToGpx(Iterable<MapFeature> features,{String name='SARCADE'}){
  String pt(String tag,LatLng p)=>'<$tag lat="${_n(p.latitude)}" lon="${_n(p.longitude)}"/>';
  final b=StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="SARCADE" xmlns="http://www.topografix.com/GPX/1/1"><metadata><name>${_esc(name)}</name></metadata>\n');
  for(final f in features.where((f)=>f.kind==FeatureKind.point||f.kind==FeatureKind.text)){
    final p=f.points.first;
    b.write('<wpt lat="${_n(p.latitude)}" lon="${_n(p.longitude)}"><name>${_esc(_name(f))}</name></wpt>\n');
  }
  for(final f in features.where((f)=>f.kind!=FeatureKind.point&&f.kind!=FeatureKind.text)){
    final pts=f.isClosed?[..._outline(f),_outline(f).first]:f.points;
    b.write('<trk><name>${_esc(_name(f))}</name><trkseg>${pts.map((p)=>pt('trkpt',p)).join()}</trkseg></trk>\n');
  }
  b.write('</gpx>\n');
  return b.toString();
}

/// Bytes of [features] in [format].
List<int> exportFeatures(Iterable<MapFeature> features,ExportFormat format)=>switch(format){
  ExportFormat.geojson=>utf8.encode(const JsonEncoder.withIndent('  ').convert(featureCollection(features))),
  ExportFormat.kml=>utf8.encode(featuresToKml(features)),
  ExportFormat.gpx=>utf8.encode(featuresToGpx(features)),
};
