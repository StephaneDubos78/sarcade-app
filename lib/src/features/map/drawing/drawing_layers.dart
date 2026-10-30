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
  final closed=features.where((f)=>f.kind==FeatureKind.zone||f.kind==FeatureKind.rectangle).toList();
  final circles=features.where((f)=>f.kind==FeatureKind.circle).toList();
  final lines=features.where((f)=>f.kind.isLinear).toList();

  final labels=<Marker>[];
  final symbols=<Marker>[];
  for(final f in features){
    final selected=c.isSelected(f.id);
    switch(f.kind){
      case FeatureKind.point:
        symbols.add(Marker(point:f.points[0],width:40,height:40,alignment:Alignment.topCenter,child:Icon(Icons.place,size:38,color:_c(f.color).withValues(alpha:f.opacity),shadows:selected?const [Shadow(color:Colors.white,blurRadius:6)]:null)));
        if(f.label.isNotEmpty)labels.add(_label(f.points[0],f.label,f.color,below:true,opacity:f.opacity));
      case FeatureKind.text:
        symbols.add(Marker(point:f.points[0],width:textMarkerWidth(f.fontSize),height:textMarkerHeight(f.fontSize),child:Center(child:_faded(f.opacity,_TextChip(text:f.label.isEmpty?'Texte':f.label,color:f.color,selected:selected,fontSize:f.fontSize)))));
      case FeatureKind.arrow:
        if(f.points.length>=2){
          final a=f.points[f.points.length-2], b=f.points.last;
          final angle=bearingDeg(a,b)*math.pi/180;
          final size=18+f.strokeWidth*3;
          symbols.add(Marker(point:b,width:size,height:size,child:Transform.rotate(angle:angle,child:Icon(Icons.navigation,size:size,color:_c(f.color).withValues(alpha:f.opacity)))));
        }
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color,opacity:f.opacity));
      case FeatureKind.measure:
        labels.add(_label(f.points.last,formatDistance(f.lengthM),f.color,opacity:f.opacity));
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color,opacity:f.opacity));
      default:
        if(f.label.isNotEmpty)labels.add(_label(f.anchor,f.label,f.color,opacity:f.opacity));
    }
  }

  return [
    if(closed.isNotEmpty)PolygonLayer(polygons:closed.map((f)=>Polygon(
      points:f.ring,color:_c(f.color).withAlpha(((c.isSelected(f.id)?80:50)*f.opacity).round()),
      borderColor:_c(f.color).withValues(alpha:f.opacity),borderStrokeWidth:f.strokeWidth,
    )).toList()),
    if(circles.isNotEmpty)CircleLayer(circles:circles.map((f)=>CircleMarker(
      point:f.points[0],radius:f.radiusM??1,useRadiusInMeter:true,
      color:_c(f.color).withAlpha(((c.isSelected(f.id)?80:50)*f.opacity).round()),borderColor:_c(f.color).withValues(alpha:f.opacity),borderStrokeWidth:f.strokeWidth,
    )).toList()),
    if(lines.isNotEmpty)PolylineLayer(polylines:lines.map((f)=>Polyline(
      points:f.points,color:_c(f.color).withValues(alpha:f.opacity),strokeWidth:f.strokeWidth,
      pattern:f.kind==FeatureKind.measure?StrokePattern.dashed(segments:const [12,8]):const StrokePattern.solid(),
      borderColor:Colors.white.withValues(alpha:f.opacity),borderStrokeWidth:c.isSelected(f.id)?3:1,
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
  final vertices=MarkerLayer(markers:d.map((p)=>Marker(point:p,width:vertexHandlePx,height:vertexHandlePx,child:_vertexDot(color))).toList());
  if(t==FeatureKind.zone&&d.length>=3){
    return [PolygonLayer(polygons:[Polygon(points:d,color:color.withAlpha(40),borderColor:color,borderStrokeWidth:c.strokeWidth,pattern:StrokePattern.dashed(segments:const [10,6]))]),vertices];
  }
  if(d.length>=2){
    return [PolylineLayer(polylines:[Polyline(points:d,color:color,strokeWidth:c.strokeWidth,pattern:StrokePattern.dashed(segments:const [10,6]))]),vertices];
  }
  return [vertices];
}

/// Child drawn with the transparency of its object (no extra layer at 100 %).
Widget _faded(double opacity,Widget child)=>opacity>=1?child:Opacity(opacity:opacity,child:child);

Marker _label(LatLng p,String text,int color,{bool below=false,double opacity=1})=>Marker(
  point:p,width:180,height:30,alignment:below?Alignment.bottomCenter:Alignment.center,
  child:IgnorePointer(child:Center(child:_faded(opacity,Container(
    padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
    decoration:BoxDecoration(color:Colors.white.withAlpha(230),borderRadius:BorderRadius.circular(4),border:Border.all(color:_c(color))),
    child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:Colors.black87)),
  )))),
);

class _TextChip extends StatelessWidget {
  final String text; final int color; final bool selected; final double fontSize;
  const _TextChip({required this.text,required this.color,required this.selected,required this.fontSize});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
    decoration:BoxDecoration(color:Colors.white.withAlpha(235),borderRadius:BorderRadius.circular(6),border:Border.all(color:_c(color),width:selected?3:1.5)),
    child:Text(text,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:TextStyle(fontSize:fontSize,fontWeight:FontWeight.bold,color:_c(color))),
  );
}

/// Size of the marker of a Texte object, growing with its font size.
double textMarkerWidth(double fontSize)=>(fontSize*13).clamp(200.0,640.0);
double textMarkerHeight(double fontSize)=>(fontSize*2.6+10).clamp(48.0,220.0);

/// Editing handles (card « Dessin, poignées d'édition », reminder of
/// 30 Oct 2026, 10 h 39, validated 10 h 40): vertex dot of 8 px, white with
/// the colour of the object as border; move handle = arrowed cross of 12 px
/// without a circle; every handle inside an invisible touch area of 44 px;
/// discreet dots in the middle of the sides to add a vertex.
const vertexHandlePx=8.0, moveHandlePx=12.0, handleTouchPx=44.0, midHandlePx=6.0;

Widget _vertexDot(Color color)=>Center(child:Container(width:vertexHandlePx,height:vertexHandlePx,
  decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,border:Border.all(color:color,width:1.5),
    boxShadow:const [BoxShadow(blurRadius:2,color:Colors.black38)])));

/// Middle of each side of [f] where a vertex can be added: (index of the
/// new vertex, point). Lines, arrows, measures and zones only.
List<(int,LatLng)> sideMiddles(MapFeature f){
  final kinds={FeatureKind.line,FeatureKind.arrow,FeatureKind.zone,FeatureKind.measure};
  if(!kinds.contains(f.kind)||f.points.length<2||f.points.length>60)return const [];
  final p=f.points, n=f.kind==FeatureKind.zone?p.length:p.length-1;
  return [for(var i=0;i<n;i++)(i+1,LatLng((p[i].latitude+p[(i+1)%p.length].latitude)/2,(p[i].longitude+p[(i+1)%p.length].longitude)/2))];
}

/// Draggable handles of the selection: vertex, corner, radius and side
/// handles for one object, then the move handle (the centre of all the
/// selected objects when several are selected). [toLatLng] converts a
/// global pointer position to map coordinates.
Widget buildHandleLayer(DrawingController c,LatLng Function(Offset global) toLatLng){
  final all=c.selection;
  if(all.isEmpty)return const SizedBox.shrink();
  final f=all.first;
  final markers=<Marker>[];
  Marker handle(LatLng p,Widget look,{required void Function(LatLng from,LatLng to) onDrag,VoidCallback? onStart,String? key})=>Marker(
    point:p,width:handleTouchPx,height:handleTouchPx,
    child:_Handle(key:key==null?null:ValueKey(key),look:look,toLatLng:toLatLng,onStart:onStart??c.beginEdit,onDrag:onDrag,onEnd:c.endEdit),
  );
  final colour=_c(f.color);
  if(all.length==1){
    switch(f.kind){
      case FeatureKind.circle:
        final center=f.points[0];
        markers.add(handle(destination(center,f.radiusM??1,90),_vertexDot(colour),onDrag:(_,to)=>c.setRadius(distanceM(center,to))));
      case FeatureKind.rectangle:
        for(var i=0;i<2;i++){markers.add(handle(f.points[i],_vertexDot(colour),onDrag:(_,to)=>c.moveVertex(i,to)));}
      case FeatureKind.line:
      case FeatureKind.arrow:
      case FeatureKind.zone:
      case FeatureKind.measure:
        if(f.points.length<=60){
          for(final (i,m) in sideMiddles(f)){
            markers.add(handle(m,Center(child:Container(width:midHandlePx,height:midHandlePx,
                decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.85),shape:BoxShape.circle,border:Border.all(color:colour.withValues(alpha:0.7))))),
              onStart:(){c.beginEdit();c.insertVertex(i,m);},onDrag:(_,to)=>c.moveVertex(i,to)));
          }
          for(var i=0;i<f.points.length;i++){markers.add(handle(f.points[i],_vertexDot(colour),onDrag:(_,to)=>c.moveVertex(i,to)));}
        }
      default:
        break;
    }
  }
  // Move handle last so it stays on top of the others.
  final anchors=[for(final x in all)x.anchor];
  final centre=LatLng(anchors.map((a)=>a.latitude).reduce((a,b)=>a+b)/anchors.length,anchors.map((a)=>a.longitude).reduce((a,b)=>a+b)/anchors.length);
  markers.add(handle(centre,Center(child:Icon(Icons.open_with,size:moveHandlePx,color:colour,shadows:const [Shadow(blurRadius:3,color:Colors.white),Shadow(blurRadius:2,color:Colors.black54)])),
    key:'move-handle',onDrag:(from,to)=>c.moveSelected(to.latitude-from.latitude,to.longitude-from.longitude)));
  return MarkerLayer(markers:markers);
}

class _Handle extends StatefulWidget {
  final Widget look;
  final LatLng Function(Offset) toLatLng;
  final VoidCallback onStart, onEnd;
  final void Function(LatLng from,LatLng to) onDrag;
  const _Handle({super.key,required this.look,required this.toLatLng,required this.onStart,required this.onDrag,required this.onEnd});
  @override State<_Handle> createState()=>_HandleState();
}

class _HandleState extends State<_Handle> {
  LatLng? _last;
  @override Widget build(BuildContext context)=>MouseRegion(cursor:SystemMouseCursors.move,child:GestureDetector(
    behavior:HitTestBehavior.opaque,
    onPanStart:(d){_last=widget.toLatLng(d.globalPosition);widget.onStart();},
    onPanUpdate:(d){final to=widget.toLatLng(d.globalPosition);final from=_last??to;_last=to;widget.onDrag(from,to);},
    onPanEnd:(_){_last=null;widget.onEnd();},
    child:SizedBox(width:handleTouchPx,height:handleTouchPx,child:widget.look),
  ));
}
