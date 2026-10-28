import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' as geo;
import 'bearing_models.dart';

/// Bearings on the map: cone, line, point where taken; crossings and the
/// probable zone of each search; the bearing being taken, in bold.
List<Widget> buildBearingLayers({required Iterable<Bearing> bearings,Bearing? draft,
    required void Function(Bearing) onTapBearing,required void Function(LatLng centre,String search) onTapZone}){
  final groups=bySearch(bearings);
  final cones=<Polygon>[], lines=<Polyline>[], markers=<Marker>[], circles=<CircleMarker>[];
  void add(Bearing b,{bool live=false}){
    final c=Color(searchColor(b.search)); final (l,r)=b.cone;
    cones.add(Polygon(points:[b.origin,l,r],color:c.withValues(alpha:live?0.16:0.10),borderColor:c.withValues(alpha:0.35),borderStrokeWidth:1));
    lines.add(Polyline(points:[b.origin,b.end],color:c,strokeWidth:live?3.5:2.2));
  }
  for(final b in bearings){add(b);}
  if(draft!=null)add(draft,live:true);
  for(final b in bearings){
    final c=Color(searchColor(b.search));
    markers.add(Marker(point:b.origin,width:30,height:30,child:Tooltip(message:'${b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}° · ${b.createdBy}',
      child:GestureDetector(onTap:()=>onTapBearing(b),child:Container(decoration:BoxDecoration(color:Colors.black54,shape:BoxShape.circle,border:Border.all(color:c,width:2.5)),
        child:Icon(Icons.track_changes,size:16,color:c))))));
  }
  for(final e in groups.entries){
    final z=probableZone(e.value);
    final c=Color(searchColor(e.key));
    for(final p in z.crossings){circles.add(CircleMarker(point:p,radius:4,color:c));}
    if(z.centre==null)continue;
    circles.add(CircleMarker(point:z.centre!,radius:z.radiusM,useRadiusInMeter:true,color:const Color(0x22FF4D5E),borderColor:const Color(0xFFFF4D5E),borderStrokeWidth:1.5));
    markers.add(Marker(point:z.centre!,width:220,height:30,alignment:Alignment.centerRight,child:GestureDetector(onTap:()=>onTapZone(z.centre!,e.key),
      child:Align(alignment:Alignment.centerLeft,child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
        decoration:BoxDecoration(color:const Color(0xF21A0B0F),borderRadius:BorderRadius.circular(6),border:Border.all(color:const Color(0xFFFF4D5E))),
        child:Text(S.t('bearings.zone',{'r':geo.formatDistance(z.radiusM),'n':z.bearings}),style:const TextStyle(fontSize:11,color:Color(0xFFFFC2C8))))))));
  }
  return [
    if(cones.isNotEmpty)PolygonLayer(polygons:cones),
    if(lines.isNotEmpty)PolylineLayer(polylines:lines),
    if(circles.isNotEmpty)CircleLayer(circles:circles),
    if(markers.isNotEmpty)MarkerLayer(markers:markers),
  ];
}
