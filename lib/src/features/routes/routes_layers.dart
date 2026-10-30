import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../map/drawing/geometry.dart' show distanceM;
import 'route_models.dart';
import 'routes_controller.dart';

IconData waypointIcon(String type)=>switch(type){
  'start'=>Icons.play_circle,'finish'=>Icons.flag_circle,'checkpoint'=>Icons.verified,
  'supply'=>Icons.local_drink,_=>Icons.circle};

/// Size of the dot of a waypoint and of its touch area (card « Itinéraires,
/// taille des points », 29 Oct 2026, 3 h 43): 12 px, 44 px to touch.
// 8 px like the drawing handles (card « Dessin, poignées d'édition », 30 Oct 2026).
const waypointDotPx=8.0, waypointTouchPx=44.0;

/// Label beside a waypoint: « Ronde nord · P2 » (card « point de passage
/// introuvable sur la carte », 3 h 15).
String waypointLabel(RoutePlan r,Waypoint w)=>r.name.trim().isEmpty?w.name:'${r.name.trim()} · ${w.name}';

/// Waypoint of [ordered] nearest to [at] (touch on the line of a route).
Waypoint? nearestWaypoint(List<Waypoint> ordered,LatLng at){
  Waypoint? best; var d=double.infinity;
  for(final w in ordered){final x=distanceM(w.point,at);if(x<d){d=x;best=w;}}
  return best;
}

/// Map layers: route lines (straight or along paths), waypoints, road
/// closures (red, dashed) and the itinerary being followed. A touch on a
/// waypoint or on the line of a route calls [onWaypointTap] (on the line:
/// the nearest waypoint), through [lineHits].
List<Widget> buildRouteLayers(RoutesController c,{String? selectedRouteId,List<LatLng> itinerary=const [],
    List<LatLng> draftClosure=const [],void Function(Waypoint)? onWaypointTap,LayerHitNotifier<String>? lineHits}){
  final lines=<Polyline>[]; final routeLines=<Polyline<String>>[];
  final markers=<Marker>[];
  for(final r in c.routes){
    final ordered=c.ordered(r);
    final selected=r.id==selectedRouteId;
    final line=routeLine(ordered);
    if(line.length>1)routeLines.add(Polyline<String>(points:line,strokeWidth:selected?6:4,color:Color(r.color).withValues(alpha:selected?1:0.75),hitValue:r.id));
    // Legs waiting for the server computation are drawn dotted.
    for(var i=1;i<ordered.length;i++){
      if(ordered[i].legNeedsRouting){
        lines.add(Polyline(points:[ordered[i-1].point,ordered[i].point],strokeWidth:2,color:Colors.black54,pattern:StrokePattern.dotted()));
      }
    }
    final passed=passedWaypoints(c.passages,r.id);
    for(final w in ordered){
      final done=passed.contains(w.id);
      final colour=done?Colors.green.shade700:Color(r.color);
      final typed=w.type!='pass';
      // Dot of 12 px (icon of the type for start, finish…), label beside,
      // inside a 44 px touch area.
      markers.add(Marker(point:w.point,width:200,height:waypointTouchPx,alignment:const Alignment(0.78,0),child:Row(children:[
        GestureDetector(key:ValueKey('wp-${w.id}'),behavior:HitTestBehavior.opaque,onTap:onWaypointTap==null?null:()=>onWaypointTap(w),
          child:SizedBox(width:waypointTouchPx,height:waypointTouchPx,child:Center(child:typed
            ?Icon(waypointIcon(w.type),size:selected?14:12,color:colour,shadows:const [Shadow(blurRadius:2,color:Colors.white)])
            :Container(width:waypointDotPx,height:waypointDotPx,decoration:BoxDecoration(color:colour,shape:BoxShape.circle,
              border:Border.all(color:Colors.white,width:selected?2:1.5),boxShadow:const [BoxShadow(blurRadius:2,color:Colors.black38)]))))),
        Flexible(child:GestureDetector(onTap:onWaypointTap==null?null:()=>onWaypointTap(w),child:Container(
          padding:const EdgeInsets.symmetric(horizontal:4,vertical:1),decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.85),borderRadius:BorderRadius.circular(4)),
          child:Text(waypointLabel(r,w),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:Colors.black87))))),
      ])));
    }
  }
  for(final cl in c.closures){
    if(cl.points.length<2)continue;
    lines.add(Polyline(points:cl.points,strokeWidth:6,color:cl.active?Colors.red.shade700:Colors.grey,
      pattern:StrokePattern.dashed(segments:const [12,8])));
    if(cl.active){
      markers.add(Marker(point:cl.points[cl.points.length~/2],width:28,height:28,
        child:Tooltip(message:cl.label,child:const Icon(Icons.block,color:Colors.red,size:24))));
    }
  }
  if(draftClosure.length>1)lines.add(Polyline(points:draftClosure,strokeWidth:5,color:Colors.red,pattern:StrokePattern.dashed(segments:const [6,6])));
  if(itinerary.length>1)lines.add(Polyline(points:itinerary,strokeWidth:6,color:Colors.teal.shade600,borderStrokeWidth:2,borderColor:Colors.white));
  final routes={for(final r in c.routes)r.id:r};
  final hits=lineHits, tap=onWaypointTap;
  void onLine(){
    final h=hits?.value;
    if(h==null||h.hitValues.isEmpty||tap==null)return;
    final r=routes[h.hitValues.first];
    final w=r==null?null:nearestWaypoint(c.ordered(r),h.coordinate);
    if(w!=null)tap(w);
  }
  return [
    if(routeLines.isNotEmpty)hits==null||tap==null?PolylineLayer<String>(polylines:routeLines):MouseRegion(
      hitTestBehavior:HitTestBehavior.deferToChild,cursor:SystemMouseCursors.click,child:GestureDetector(onTap:onLine,
        child:PolylineLayer<String>(hitNotifier:hits,minimumHitbox:22,polylines:routeLines))),
    if(lines.isNotEmpty)PolylineLayer(polylines:lines),
    if(markers.isNotEmpty)MarkerLayer(markers:markers),
  ];
}
