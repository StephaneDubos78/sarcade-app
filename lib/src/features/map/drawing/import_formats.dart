import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'map_feature.dart';

/// A shape read from a file, before it becomes a [MapFeature].
class ImportedShape {
  final FeatureKind kind;
  final List<LatLng> points;
  final double? radiusM;
  final String label;
  final int? color;
  const ImportedShape({required this.kind,required this.points,this.radiusM,this.label='',this.color});
}

class ImportResult {
  final List<ImportedShape> shapes;
  /// Elements skipped because they were empty, invalid or beyond the limits.
  final int skipped;
  const ImportResult(this.shapes,this.skipped);
}

class ImportFormatException implements Exception {
  final String message;
  const ImportFormatException(this.message);
  @override String toString()=>message;
}

/// Limits kept in line with the server (sarcade-server, features/service.py).
const maxImportedShapes=2000;
const maxPointsPerShape=5000;
const _maxLabel=160;

/// Reads GPX, KML, KMZ or GeoJSON, chosen from the file name.
ImportResult parseMapFile(String fileName,List<int> bytes){
  final ext=fileName.toLowerCase().split('.').last;
  switch(ext){
    case 'gpx': return parseGpx(_text(bytes));
    case 'kml': return parseKml(_text(bytes));
    case 'kmz': return parseKmz(bytes);
    case 'geojson':
    case 'json': return parseGeoJson(_text(bytes));
    default: throw ImportFormatException('Format non pris en charge : .$ext (GPX, KML, KMZ ou GeoJSON attendu)');
  }
}

String _text(List<int> bytes){
  final s=utf8.decode(bytes,allowMalformed:true);
  return s.startsWith('﻿')?s.substring(1):s;
}

// ---------------------------------------------------------------- common

class _Collector {
  final shapes=<ImportedShape>[];
  var skipped=0;

  void add(FeatureKind kind,List<LatLng> points,{String label='',int? color,double? radiusM}){
    final valid=points.where((p)=>p.latitude.abs()<=90&&p.longitude.abs()<=180&&p.latitude.isFinite&&p.longitude.isFinite).toList();
    if(kind==FeatureKind.zone&&valid.length>1&&valid.first==valid.last)valid.removeLast();
    final minimum=switch(kind){FeatureKind.point||FeatureKind.text||FeatureKind.circle=>1,FeatureKind.zone=>3,_=>2};
    if(valid.length<minimum||shapes.length>=maxImportedShapes){skipped++;return;}
    final trimmed=label.trim();
    shapes.add(ImportedShape(
      kind:kind,points:_decimate(valid),radiusM:radiusM,color:color,
      label:trimmed.length>_maxLabel?trimmed.substring(0,_maxLabel):trimmed,
    ));
  }

  ImportResult result(){
    if(shapes.isEmpty&&skipped==0)throw const ImportFormatException('Aucun objet cartographique dans ce fichier');
    return ImportResult(shapes,skipped);
  }
}

/// Keeps long GPS tracks under the server limit, always keeping both ends.
List<LatLng> _decimate(List<LatLng> pts){
  if(pts.length<=maxPointsPerShape)return pts;
  final step=(pts.length/(maxPointsPerShape-1)).ceil();
  final out=<LatLng>[for(var i=0;i<pts.length-1;i+=step)pts[i]];
  out.add(pts.last);
  return out;
}

Iterable<XmlElement> _all(XmlNode n,String local)=>n.descendants.whereType<XmlElement>().where((e)=>e.name.local==local);
Iterable<XmlElement> _children(XmlElement e,String local)=>e.childElements.where((c)=>c.name.local==local);
String _childText(XmlElement e,String local){
  for(final c in _children(e,local)){return c.innerText.trim();}
  return '';
}

XmlDocument _parseXml(String text){
  try{return XmlDocument.parse(text);}
  on XmlException catch(e){throw ImportFormatException('Fichier XML illisible : ${e.message}');}
}

// ---------------------------------------------------------------- GPX

/// GPX 1.0/1.1: waypoints become points, routes and track segments lines.
ImportResult parseGpx(String text){
  final doc=_parseXml(text);
  if(doc.rootElement.name.local!='gpx')throw const ImportFormatException('Ce fichier n’est pas un GPX');
  final out=_Collector();
  LatLng? pt(XmlElement e){
    final lat=double.tryParse(e.getAttribute('lat')??''), lon=double.tryParse(e.getAttribute('lon')??'');
    return lat==null||lon==null?null:LatLng(lat,lon);
  }
  for(final w in _children(doc.rootElement,'wpt')){
    final p=pt(w);
    if(p==null){out.skipped++;continue;}
    out.add(FeatureKind.point,[p],label:_childText(w,'name'));
  }
  for(final r in _children(doc.rootElement,'rte')){
    out.add(FeatureKind.line,[for(final p in _children(r,'rtept').map(pt))if(p!=null)p],label:_childText(r,'name'));
  }
  for(final t in _children(doc.rootElement,'trk')){
    final name=_childText(t,'name');
    final segs=_children(t,'trkseg').toList();
    for(var i=0;i<segs.length;i++){
      final label=segs.length>1&&name.isNotEmpty?'$name (${i+1})':name;
      out.add(FeatureKind.line,[for(final p in _children(segs[i],'trkpt').map(pt))if(p!=null)p],label:label);
    }
  }
  return out.result();
}

// ---------------------------------------------------------------- KML / KMZ

List<LatLng> _kmlCoordinates(XmlElement e){
  final pts=<LatLng>[];
  for(final tuple in e.innerText.trim().split(RegExp(r'\s+'))){
    final parts=tuple.split(',');
    if(parts.length<2)continue;
    final lon=double.tryParse(parts[0]), lat=double.tryParse(parts[1]);
    if(lat!=null&&lon!=null)pts.add(LatLng(lat,lon));
  }
  return pts;
}

/// KML colours are aabbggrr; map objects use ARGB, always opaque for strokes.
int? kmlColor(String s){
  final v=s.trim();
  if(!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(v))return null;
  final bb=v.substring(2,4), gg=v.substring(4,6), rr=v.substring(6,8);
  return int.parse('FF$rr$gg$bb',radix:16);
}

/// KML 2.2: placemarks with Point, LineString, Polygon (outer ring) and
/// MultiGeometry. Colours are read from inline LineStyle/PolyStyle.
ImportResult parseKml(String text){
  final doc=_parseXml(text);
  if(doc.rootElement.name.local!='kml')throw const ImportFormatException('Ce fichier n’est pas un KML');
  final out=_Collector();
  for(final pm in _all(doc,'Placemark')){
    final name=_childText(pm,'name');
    int? color;
    for(final ls in _all(pm,'LineStyle')){color=kmlColor(_childText(ls,'color'));}
    if(color==null){for(final ps in _all(pm,'PolyStyle')){color=kmlColor(_childText(ps,'color'));}}
    var found=false;
    for(final g in _all(pm,'Point')){
      for(final c in _children(g,'coordinates')){out.add(FeatureKind.point,_kmlCoordinates(c),label:name,color:color);found=true;}
    }
    for(final g in _all(pm,'LineString')){
      for(final c in _children(g,'coordinates')){out.add(FeatureKind.line,_kmlCoordinates(c),label:name,color:color);found=true;}
    }
    for(final g in _all(pm,'Polygon')){
      for(final ob in _children(g,'outerBoundaryIs')){
        for(final c in _all(ob,'coordinates')){out.add(FeatureKind.zone,_kmlCoordinates(c),label:name,color:color);found=true;}
      }
    }
    if(!found)out.skipped++;
  }
  return out.result();
}

/// KMZ is a zip holding a KML, usually doc.kml.
ImportResult parseKmz(List<int> bytes){
  final Archive zip;
  try{zip=ZipDecoder().decodeBytes(bytes);}
  catch(_){throw const ImportFormatException('Archive KMZ illisible');}
  ArchiveFile? kml;
  for(final f in zip.files){
    if(!f.isFile||!f.name.toLowerCase().endsWith('.kml'))continue;
    if(kml==null||f.name.toLowerCase()=='doc.kml')kml=f;
  }
  if(kml==null)throw const ImportFormatException('Aucun fichier KML dans cette archive KMZ');
  return parseKml(_text(kml.content));
}

// ---------------------------------------------------------------- GeoJSON

int? _hexColor(Object? v){
  if(v is! String)return null;
  final m=RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
  return m==null?null:int.parse('FF${m.group(1)}',radix:16);
}

/// GeoJSON (RFC 7946), including the files exported by SARCADE: the
/// `sarcade:kind` property restores circles, arrows, texts and measures.
ImportResult parseGeoJson(String text){
  final Object? root;
  try{root=jsonDecode(text);}
  on FormatException{throw const ImportFormatException('Fichier GeoJSON illisible');}
  final out=_Collector();

  LatLng? pos(Object? c){
    if(c is! List||c.length<2||c[0] is! num||c[1] is! num)return null;
    return LatLng((c[1] as num).toDouble(),(c[0] as num).toDouble());
  }
  List<LatLng> line(Object? c)=>c is List?[for(final p in c.map(pos))if(p!=null)p]:const [];

  void geometry(Object? g,Map props){
    if(g is! Map){out.skipped++;return;}
    final names=[props['name'],props['title'],props['label']].whereType<String>();
    final label=names.isEmpty?'':names.first;
    final color=_hexColor(props['stroke']);
    final hint=props['sarcade:kind'];
    final coords=g['coordinates'];
    switch(g['type']){
      case 'Point':
        final p=pos(coords);
        if(p==null){out.skipped++;return;}
        final radius=props['radius_m'];
        if(hint=='circle'&&radius is num&&radius>0){out.add(FeatureKind.circle,[p],label:label,color:color,radiusM:radius.toDouble());}
        else{out.add(hint=='text'?FeatureKind.text:FeatureKind.point,[p],label:label,color:color);}
      case 'MultiPoint':
        for(final p in line(coords)){out.add(FeatureKind.point,[p],label:label,color:color);}
      case 'LineString':
        final kind=switch(hint){'arrow'=>FeatureKind.arrow,'measure'=>FeatureKind.measure,'freehand'=>FeatureKind.freehand,_=>FeatureKind.line};
        out.add(kind,line(coords),label:label,color:color);
      case 'MultiLineString':
        if(coords is List){for(final l in coords){out.add(FeatureKind.line,line(l),label:label,color:color);}}
      case 'Polygon':
        if(coords is List&&coords.isNotEmpty){out.add(FeatureKind.zone,line(coords.first),label:label,color:color);}else{out.skipped++;}
      case 'MultiPolygon':
        if(coords is List){for(final poly in coords){if(poly is List&&poly.isNotEmpty)out.add(FeatureKind.zone,line(poly.first),label:label,color:color);}}
      case 'GeometryCollection':
        final gs=g['geometries'];
        if(gs is List){for(final sub in gs){geometry(sub,props);}}
      default:
        out.skipped++;
    }
  }

  void feature(Object? f){
    if(f is! Map){out.skipped++;return;}
    final props=f['properties'] is Map?f['properties'] as Map:const {};
    geometry(f['geometry'],props);
  }

  if(root is! Map)throw const ImportFormatException('Fichier GeoJSON invalide');
  switch(root['type']){
    case 'FeatureCollection':
      final fs=root['features'];
      if(fs is List){for(final f in fs){feature(f);}}
    case 'Feature':
      feature(root);
    default:
      geometry(root,const {});
  }
  return out.result();
}
