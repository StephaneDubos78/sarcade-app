import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:latlong2/latlong.dart';

import 'map_feature.dart';

/// Converts a geographic point to a screen offset in logical pixels.
typedef Projector=Offset Function(LatLng);

/// Tolerance around strokes and points, in logical pixels. Sized for a finger.
const hitTolerancePx=16.0;

double _segmentDistance(Offset p,Offset a,Offset b){
  final ab=b-a;
  final len2=ab.dx*ab.dx+ab.dy*ab.dy;
  if(len2==0)return (p-a).distance;
  final t=(((p-a).dx*ab.dx+(p-a).dy*ab.dy)/len2).clamp(0.0,1.0);
  return (p-(a+ab*t)).distance;
}

double _polylineDistance(Offset p,List<Offset> pts,{bool closed=false}){
  if(pts.isEmpty)return double.infinity;
  if(pts.length==1)return (p-pts.first).distance;
  var best=double.infinity;
  final n=closed?pts.length:pts.length-1;
  for(var i=0;i<n;i++){best=math.min(best,_segmentDistance(p,pts[i],pts[(i+1)%pts.length]));}
  return best;
}

bool _inside(Offset p,List<Offset> ring){
  var inside=false;
  for(var i=0,j=ring.length-1;i<ring.length;j=i++){
    final a=ring[i], b=ring[j];
    if((a.dy>p.dy)!=(b.dy>p.dy)&&p.dx<(b.dx-a.dx)*(p.dy-a.dy)/(b.dy-a.dy)+a.dx)inside=!inside;
  }
  return inside;
}

/// Screen distance from [tap] to [f], 0 when inside a closed shape.
double featureDistance(MapFeature f,Offset tap,Projector project,{double Function(MapFeature)? radiusPx}){
  switch(f.kind){
    case FeatureKind.point:
    case FeatureKind.text:
      return (tap-project(f.points[0])).distance;
    case FeatureKind.circle:
      final r=radiusPx?.call(f)??0;
      final d=(tap-project(f.points[0])).distance;
      return d<=r?0:d-r;
    case FeatureKind.rectangle:
    case FeatureKind.zone:
      final ring=f.ring.map(project).toList();
      return _inside(tap,ring)?0:_polylineDistance(tap,ring,closed:true);
    default:
      return _polylineDistance(tap,f.points.map(project).toList());
  }
}

/// Topmost feature under [tap], or null. Strokes win over the inside of shapes,
/// so a line drawn across a zone stays selectable.
MapFeature? hitTest(List<MapFeature> features,Offset tap,Projector project,{double Function(MapFeature)? radiusPx}){
  MapFeature? stroke, fill;
  for(final f in features.reversed){
    final d=featureDistance(f,tap,project,radiusPx:radiusPx);
    if(d==0&&f.isClosed){fill??=f;continue;}
    if(d<=hitTolerancePx){stroke=f;break;}
  }
  return stroke??fill;
}
