import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'route_models.dart';
import 'routes_controller.dart';

IconData waypointIcon(String type)=>switch(type){
  'start'=>Icons.play_circle,'finish'=>Icons.flag_circle,'checkpoint'=>Icons.verified,
  'supply'=>Icons.local_drink,_=>Icons.circle};

/// Map layers: route lines (straight or along paths), waypoints, road
/// closures (red, dashed) and the itinerary being followed.
List<Widget> buildRouteLayers(RoutesController c,{String? selectedRouteId,List<LatLng> itinerary=const [],
    List<LatLng> draftClosure=const [],void Function(Waypoint)? onWaypointTap}){
  final lines=<Polyline>[];
  final markers=<Marker>[];
  for(final r in c.routes){
    final ordered=c.ordered(r);
    final selected=r.id==selectedRouteId;
    final line=routeLine(ordered);
    if(line.length>1)lines.add(Polyline(points:line,strokeWidth:selected?6:4,color:Color(r.color).withValues(alpha:selected?1:0.75)));
    // Legs waiting for the server computation are drawn dotted.
    for(var i=1;i<ordered.length;i++){
      if(ordered[i].legNeedsRouting){
        lines.add(Polyline(points:[ordered[i-1].point,ordered[i].point],strokeWidth:2,color:Colors.black54,pattern:StrokePattern.dotted()));
      }
    }
    final passed=passedWaypoints(c.passages,r.id);
    for(final w in ordered){
      final done=passed.contains(w.id);
      markers.add(Marker(point:w.point,width:90,height:46,alignment:Alignment.topCenter,child:GestureDetector(
        onTap:onWaypointTap==null?null:()=>onWaypointTap(w),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Icon(waypointIcon(w.type),size:selected?26:20,color:done?Colors.green.shade700:Color(r.color)),
          Container(padding:const EdgeInsets.symmetric(horizontal:4),decoration:BoxDecoration(color:Colors.white70,borderRadius:BorderRadius.circular(4)),
            child:Text(w.name,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w600))),
        ]),
      )));
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
  return [
    if(lines.isNotEmpty)PolylineLayer(polylines:lines),
    if(markers.isNotEmpty)MarkerLayer(markers:markers),
  ];
}
