import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' as geo;
import 'bearing_models.dart';

/// Bearings on the map: cone, line, point where taken; crossings and the
/// probable zone of each search; the bearing being taken, in bold.
/// Line and cone take the colour of the signal (crossings readable), or of
/// the operator when [byOperator]; the dot where it was taken always the
/// operator's, with initials.
List<Widget> buildBearingLayers({required Iterable<Bearing> bearings,Bearing? draft,bool byOperator=false,LayerHitNotifier<Bearing>? hits,
    required void Function(Bearing) onTapBearing,required void Function(LatLng centre,String search) onTapZone}){
  final groups=bySearch(bearings);
  final cones=<Polygon>[], lines=<Polyline<Bearing>>[], markers=<Marker>[], circles=<CircleMarker>[];
  void add(Bearing b,{bool live=false}){
    final c=Color(byOperator?(b.operatorColor??operatorColor(b.createdBy)):searchColor(b.search)); final (l,r)=b.cone;
    cones.add(Polygon(points:[b.origin,l,r],color:c.withValues(alpha:live?0.16:0.10),borderColor:c.withValues(alpha:0.35),borderStrokeWidth:1));
    lines.add(Polyline<Bearing>(points:[b.origin,b.end],color:c,strokeWidth:live?3.5:2.2,hitValue:live?null:b));
  }
  for(final b in bearings){add(b);}
  if(draft!=null)add(draft,live:true);
  for(final b in bearings){
    final op=Color(b.operatorColor??operatorColor(b.createdBy)), line=byOperator?op:Color(searchColor(b.search));
    markers.add(Marker(point:b.origin,width:30,height:30,child:Tooltip(message:['${b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}°',b.createdBy,if(b.search.isNotEmpty)b.search].join(' · '),
      child:GestureDetector(onTap:()=>onTapBearing(b),child:Container(alignment:Alignment.center,
        decoration:BoxDecoration(color:op,shape:BoxShape.circle,border:Border.all(color:line,width:2.5)),
        child:Text(operatorInitials(b.createdBy),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:Colors.white,height:1)))))));
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
    // The whole line selects the bearing (« Relevés, sélection »), not only
    // the dot often hidden under an operator; wide touch area around it.
    if(lines.isNotEmpty)hits==null?PolylineLayer<Bearing>(polylines:lines):MouseRegion(hitTestBehavior:HitTestBehavior.deferToChild,
      cursor:SystemMouseCursors.click,child:GestureDetector(
        onTap:(){final h=hits.value;if(h!=null&&h.hitValues.isNotEmpty)onTapBearing(h.hitValues.first);},
        child:PolylineLayer<Bearing>(hitNotifier:hits,minimumHitbox:24,polylines:lines))),
    if(circles.isNotEmpty)CircleLayer(circles:circles),
    if(markers.isNotEmpty)MarkerLayer(markers:markers),
  ];
}
