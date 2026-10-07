import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'drawing_controller.dart';
import 'geometry.dart';
import 'map_feature.dart';

Color _c(int argb)=>Color(argb);

/// Map layers for the drawn objects and the shape in progress.
/// Placed above the tiles and traces, below the operator markers.
List<Widget> buildDrawingLayers(DrawingController c){
  final features=c.features;
  final selectedId=c.selected?.id;
  final closed=features.where((f)=>f.kind==FeatureKind.zone||f.kind==FeatureKind.rectangle).toList();
  final circles=features.where((f)=>f.kind==FeatureKind.circle).toList();
  final lines=features.where((f)=>f.kind.isLinear).toList();

  final labels=<Marker>[];
  final symbols=<Marker>[];
  for(final f in features){
    final selected=f.id==selectedId;
    switch(f.kind){
      case FeatureKind.point:
        symbols.add(Marker(point:f.points[0],width:40,height:40,alignment:Alignment.topCenter,child:Icon(Icons.place,size:38,color:_c(f.color),shadows:selected?const [Shadow(color:Colors.white,blurRadius:6)]:null)));
        if(f.label.isNotEmpty)labels.add(_label(f.points[0],f.label,f.color,below:true));
      case FeatureKind.text:
        symbols.add(Marker(point:f.points[0],width:200,height:48,child:Center(child:_TextChip(text:f.label.isEmpty?'Texte':f.label,color:f.color,selected:selected))));
      case FeatureKind.arrow:
        if(f.points.length>=2){
          final a=f.points[f.points.length-2], b=f.points.last;
          final angle=bearingDeg(a,b)*math.pi/180;
          final size=18+f.strokeWidth*3;
          symbols.add(Marker(point:b,width:size,height:size,child:Transform.rotate(angle:angle,child:Icon(Icons.navigation,size:size,color:_c(f.color)))));
        }
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color));
      case FeatureKind.measure:
        labels.add(_label(f.points.last,formatDistance(f.lengthM),f.color));
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color));
      default:
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color));
    }
  }

  return [
    if(closed.isNotEmpty)PolygonLayer(polygons:closed.map((f)=>Polygon(
      points:f.ring,color:_c(f.color).withAlpha(f.id==selectedId?80:50),
      borderColor:_c(f.color),borderStrokeWidth:f.strokeWidth,
    )).toList()),
    if(circles.isNotEmpty)CircleLayer(circles:circles.map((f)=>CircleMarker(
      point:f.points[0],radius:f.radiusM??1,useRadiusInMeter:true,
      color:_c(f.color).withAlpha(f.id==selectedId?80:50),borderColor:_c(f.color),borderStrokeWidth:f.strokeWidth,
    )).toList()),
    if(lines.isNotEmpty)PolylineLayer(polylines:lines.map((f)=>Polyline(
      points:f.points,color:_c(f.color),strokeWidth:f.strokeWidth,
      pattern:f.kind==FeatureKind.measure?StrokePattern.dashed(segments:const [12,8]):const StrokePattern.solid(),
      borderColor:Colors.white,borderStrokeWidth:f.id==selectedId?3:1,
      strokeCap:StrokeCap.round,strokeJoin:StrokeJoin.round,
    )).toList()),
    ..._draftLayers(c),
    if(symbols.isNotEmpty||labels.isNotEmpty)MarkerLayer(markers:[...symbols,...labels]),
  ];
}

List<Widget> _draftLayers(DrawingController c){
  final t=c.tool, d=c.draft;
  if(t==null||d.isEmpty)return const [];
  final color=_c(c.color);
  final vertices=MarkerLayer(markers:d.map((p)=>Marker(point:p,width:16,height:16,child:Container(decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:color,width:3))))).toList());
  if(t==FeatureKind.zone&&d.length>=3){
    return [PolygonLayer(polygons:[Polygon(points:d,color:color.withAlpha(40),borderColor:color,borderStrokeWidth:c.strokeWidth,pattern:StrokePattern.dashed(segments:const [10,6]))]),vertices];
  }
  if(d.length>=2){
    return [PolylineLayer(polylines:[Polyline(points:d,color:color,strokeWidth:c.strokeWidth,pattern:StrokePattern.dashed(segments:const [10,6]))]),vertices];
  }
  return [vertices];
}

Marker _label(LatLng p,String text,int color,{bool below=false})=>Marker(
  point:p,width:180,height:30,alignment:below?Alignment.bottomCenter:Alignment.center,
  child:IgnorePointer(child:Center(child:Container(
    padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
    decoration:BoxDecoration(color:Colors.white.withAlpha(230),borderRadius:BorderRadius.circular(4),border:Border.all(color:_c(color))),
    child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Colors.black87)),
  ))),
);

class _TextChip extends StatelessWidget {
  final String text; final int color; final bool selected;
  const _TextChip({required this.text,required this.color,required this.selected});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
    decoration:BoxDecoration(color:Colors.white.withAlpha(235),borderRadius:BorderRadius.circular(6),border:Border.all(color:_c(color),width:selected?3:1.5)),
    child:Text(text,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:TextStyle(fontSize:15,fontWeight:FontWeight.bold,color:_c(color))),
  );
}

/// Draggable handles for the selected object: one move handle, plus vertex,
/// corner or radius handles depending on the kind. [toLatLng] converts a global
/// pointer position to map coordinates.
Widget buildHandleLayer(DrawingController c,LatLng Function(Offset global) toLatLng){
  final f=c.selected;
  if(f==null)return const SizedBox.shrink();
  final markers=<Marker>[];
  Marker handle(LatLng p,IconData? icon,{required void Function(LatLng from,LatLng to) onDrag,double size=34})=>Marker(
    point:p,width:size,height:size,
    child:_Handle(icon:icon,color:_c(f.color),toLatLng:toLatLng,onStart:c.beginEdit,onDrag:onDrag,onEnd:c.endEdit),
  );

  switch(f.kind){
    case FeatureKind.circle:
      final center=f.points[0];
      markers.add(handle(destination(center,f.radiusM??1,90),Icons.open_in_full,size:30,onDrag:(_,to)=>c.setRadius(distanceM(center,to))));
    case FeatureKind.rectangle:
      for(var i=0;i<2;i++){markers.add(handle(f.points[i],null,size:26,onDrag:(_,to)=>c.moveVertex(i,to)));}
    case FeatureKind.line:
    case FeatureKind.arrow:
    case FeatureKind.zone:
    case FeatureKind.measure:
      if(f.points.length<=60){
        for(var i=0;i<f.points.length;i++){markers.add(handle(f.points[i],null,size:26,onDrag:(_,to)=>c.moveVertex(i,to)));}
      }
    default:
      break;
  }
  // Move handle last so it stays on top of vertex handles.
  markers.add(handle(f.anchor,Icons.open_with,size:40,onDrag:(from,to)=>c.moveSelected(to.latitude-from.latitude,to.longitude-from.longitude)));
  return MarkerLayer(markers:markers);
}

class _Handle extends StatefulWidget {
  final IconData? icon; final Color color;
  final LatLng Function(Offset) toLatLng;
  final VoidCallback onStart, onEnd;
  final void Function(LatLng from,LatLng to) onDrag;
  const _Handle({required this.icon,required this.color,required this.toLatLng,required this.onStart,required this.onDrag,required this.onEnd});
  @override State<_Handle> createState()=>_HandleState();
}

class _HandleState extends State<_Handle> {
  LatLng? _last;
  @override Widget build(BuildContext context)=>GestureDetector(
    behavior:HitTestBehavior.opaque,
    onPanStart:(d){_last=widget.toLatLng(d.globalPosition);widget.onStart();},
    onPanUpdate:(d){final to=widget.toLatLng(d.globalPosition);final from=_last??to;_last=to;widget.onDrag(from,to);},
    onPanEnd:(_){_last=null;widget.onEnd();},
    child:Container(
      decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:widget.color,width:3),boxShadow:const [BoxShadow(blurRadius:3,color:Colors.black38)]),
      child:widget.icon==null?null:Icon(widget.icon,size:20,color:widget.color),
    ),
  );
}
