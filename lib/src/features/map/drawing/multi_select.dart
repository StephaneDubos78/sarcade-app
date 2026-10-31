/// « Dessin, sélection multiple » (6 proposals validated on 29 Oct 2026,
/// 3 h 43): selection rectangle, objects touched by it, own objects only
/// (all for the PCO), the common action bar.
library;

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/strings.dart';
import 'drawing_controller.dart';
import 'hit_test.dart';
import 'map_feature.dart';
import '../../../ui/color_palette.dart';
import 'export_formats.dart';

/// Proposal 6: one's own objects, or every one for the PCO.
bool canMultiSelect(MapFeature f,String actorId,{required bool pco})=>pco||f.createdBy==null||f.createdBy==actorId;

/// Rectangle drawn on the screen from two corners.
Rect selectionRect(Offset a,Offset b)=>Rect.fromPoints(a,b);

bool _segmentHits(Rect r,Offset a,Offset b){
  if(r.contains(a)||r.contains(b))return true;
  bool cross(Offset p1,Offset p2,Offset q1,Offset q2){
    double o(Offset a,Offset b,Offset c)=>(b.dx-a.dx)*(c.dy-a.dy)-(b.dy-a.dy)*(c.dx-a.dx);
    final d1=o(q1,q2,p1), d2=o(q1,q2,p2), d3=o(p1,p2,q1), d4=o(p1,p2,q2);
    return (d1*d2<0)&&(d3*d4<0);
  }
  final c=[r.topLeft,r.topRight,r.bottomRight,r.bottomLeft];
  for(var i=0;i<4;i++){if(cross(a,b,c[i],c[(i+1)%4]))return true;}
  return false;
}

/// Objects whose outline is touched by the rectangle (proposal 1): a
/// vertex inside, a side crossing it, or the rectangle inside a shape.
List<MapFeature> featuresInRect(Iterable<MapFeature> features,Rect r,Projector project,{double Function(MapFeature)? radiusPx}){
  final out=<MapFeature>[];
  for(final f in features){
    final pts=(f.isClosed&&f.kind!=FeatureKind.circle?f.ring:f.points).map(project).toList();
    var hit=false;
    if(f.kind==FeatureKind.circle){
      final c=pts.first, rad=radiusPx?.call(f)??0;
      final nx=c.dx.clamp(r.left,r.right), ny=c.dy.clamp(r.top,r.bottom);
      final d=(Offset(nx,ny)-c).distance;
      hit=d<=rad;
    }else if(pts.length==1){
      hit=r.inflate(hitTolerancePx/2).contains(pts.first);
    }else{
      final n=f.isClosed?pts.length:pts.length-1;
      for(var i=0;i<n&&!hit;i++){hit=_segmentHits(r,pts[i],pts[(i+1)%pts.length]);}
      if(!hit&&f.isClosed)hit=featureDistance(f,r.center,project)==0;
    }
    if(hit)out.add(f);
  }
  return out;
}

/// GeoJSON of the selected objects (proposal 3, « exporter en GeoJSON »).
List<int> selectionGeoJson(Iterable<MapFeature> features)=>utf8.encode(const JsonEncoder.withIndent('  ').convert(featureCollection(features)));

/// Common action bar of a multiple selection (proposal 3): number of
/// objects, colour, width, duplicate, delete (one confirmation), export.
/// Moving together uses the move handle at the centre of the selection.
class MultiSelectionBar extends StatelessWidget {
  /// « Exporter », format chosen (card of 30 Oct 2026, 17 h 41).
  final DrawingController controller; final ValueChanged<ExportFormat> onExport;
  const MultiSelectionBar({super.key,required this.controller,required this.onExport});

  @override Widget build(BuildContext context){
    final c=controller, all=c.selection;
    if(all.length<2)return const SizedBox.shrink();
    final first=all.first;
    return Material(key:const ValueKey('multi-selection-bar'),elevation:4,borderRadius:BorderRadius.circular(14),color:Theme.of(context).colorScheme.surface,
      child:SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),child:Row(mainAxisSize:MainAxisSize.min,children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:Text(S.t('draw.selectedN',{'n':all.length}),style:Theme.of(context).textTheme.labelLarge)),
        ColorPaletteButton(color:first.color,onSelected:c.setColor),
        PopupMenuButton<double>(
          tooltip:S.t('draw.width'),onSelected:c.setStrokeWidth,
          itemBuilder:(_)=>[for(final w in drawingWidths)PopupMenuItem(value:w,child:SizedBox(width:48,child:Divider(thickness:w,color:Colors.black87)))],
          child:const Padding(padding:EdgeInsets.all(10),child:Icon(Icons.line_weight)),
        ),
        IconButton(tooltip:S.t('draw.duplicate'),onPressed:c.duplicateSelected,icon:const Icon(Icons.copy_all_outlined)),
        // « Exporter » under the icon, then GeoJSON, KML or GPX; for everyone.
        PopupMenuButton<ExportFormat>(key:const ValueKey('multi-export'),tooltip:S.t('draw.export'),onSelected:onExport,
          itemBuilder:(_)=>[for(final f in ExportFormat.values)PopupMenuItem(value:f,child:Text(f.label))],
          child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.file_download_outlined),Text(S.t('draw.exportShort'),style:const TextStyle(fontSize:11)),
          ]))),
        IconButton(key:const ValueKey('multi-delete'),tooltip:S.t('routes.delete'),onPressed:()=>deleteSelection(context,c),icon:const Icon(Icons.delete_outline),color:Colors.red.shade700),
        IconButton(tooltip:S.t('draw.deselect'),onPressed:c.endSelection,icon:const Icon(Icons.close)),
      ])));
  }
}

/// Font size button of the selection bar of a Texte object.
Widget fontSizeButton(DrawingController c,MapFeature f)=>PopupMenuButton<double>(
  key:const ValueKey('font-size'),tooltip:S.t('draw.fontSize'),onSelected:c.setFontSize,
  itemBuilder:(_)=>[for(final s in textFontSizes)CheckedPopupMenuItem(value:s,checked:(f.fontSize-s).abs()<0.5,
    child:Text('${s.round()}',style:TextStyle(fontSize:s.clamp(11,24).toDouble(),fontWeight:FontWeight.bold)))],
  child:const Padding(padding:EdgeInsets.all(10),child:Icon(Icons.format_size)),
);

/// Delete of a multiple selection: one confirmation for all (proposal 3);
/// a single object is deleted at once, as before.
Future<void> deleteSelection(BuildContext context,DrawingController c) async {
  if(!c.isMulti){c.deleteSelected();return;}
  final n=c.selection.length;
  final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
    title:Text(S.t('draw.deleteN',{'n':n})),content:Text(S.t('draw.deleteNHelp')),
    actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(d,true),child:Text(S.t('routes.delete')))]));
  if(ok==true)c.deleteSelected();
}

/// Selection rectangle. Maj + glisser on a computer always draws it. In the
/// « Sélectionner une zone » mode (card C1 of the cinématique review, 31 Oct
/// 2026), a plain drag moves the map ([onMove], pinch and wheel zoom too)
/// and the rectangle starts with a long press, then a drag; without
/// [onMove], every drag draws it. A touch without a drag selects one object.
class SelectionRectOverlay extends StatefulWidget {
  final void Function(Rect rect) onRect; final void Function(Offset at) onTap;
  final void Function(ScaleStartDetails d)? onMoveStart;
  final void Function(ScaleUpdateDetails d)? onMove;
  final void Function(PointerScrollEvent e)? onWheel;
  const SelectionRectOverlay({super.key,required this.onRect,required this.onTap,this.onMoveStart,this.onMove,this.onWheel});
  @override State<SelectionRectOverlay> createState()=>_SelectionRectOverlayState();
}

class _SelectionRectOverlayState extends State<SelectionRectOverlay> {
  Offset? _a, _b;
  void _start(Offset p)=>setState((){_a=p;_b=p;});
  void _update(Offset p)=>setState(()=>_b=p);
  void _end(){final a=_a, b=_b;setState((){_a=null;_b=null;});if(a!=null&&b!=null&&a!=b)widget.onRect(selectionRect(a,b));}
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme; final a=_a, b=_b;
    final moves=widget.onMove!=null;
    final box=MouseRegion(cursor:moves?SystemMouseCursors.grab:SystemMouseCursors.precise,child:Stack(children:[
      if(a!=null&&b!=null)Positioned.fromRect(rect:selectionRect(a,b),child:Container(decoration:BoxDecoration(
        color:s.primary.withValues(alpha:0.10),border:Border.all(color:s.primary,width:1.5)))),
    ]));
    final detector=moves
      ? GestureDetector(key:const ValueKey('selection-rect'),behavior:HitTestBehavior.opaque,
          onTapUp:(d)=>widget.onTap(d.localPosition),
          onLongPressStart:(d)=>_start(d.localPosition),
          onLongPressMoveUpdate:(d)=>_update(d.localPosition),
          onLongPressEnd:(_)=>_end(),
          onScaleStart:widget.onMoveStart,
          onScaleUpdate:widget.onMove,
          child:box)
      : GestureDetector(key:const ValueKey('selection-rect'),behavior:HitTestBehavior.opaque,
          onTapUp:(d)=>widget.onTap(d.localPosition),
          onPanStart:(d)=>_start(d.localPosition),
          onPanUpdate:(d)=>_update(d.localPosition),
          onPanEnd:(_)=>_end(),
          child:box);
    return Listener(onPointerSignal:(e){if(e is PointerScrollEvent)widget.onWheel?.call(e);},child:detector);
  }
}

/// Follows the Maj key wherever the focus is (Maj + glisser draws the
/// selection rectangle on a computer); no size.
class ShiftWatcher extends StatefulWidget {
  final ValueChanged<bool> onChanged;
  const ShiftWatcher({super.key,required this.onChanged});
  @override State<ShiftWatcher> createState()=>_ShiftWatcherState();
}

class _ShiftWatcherState extends State<ShiftWatcher> {
  bool _down=false;
  bool _on(KeyEvent _){final d=HardwareKeyboard.instance.isShiftPressed;if(d!=_down){_down=d;widget.onChanged(d);}return false;}
  @override void initState(){super.initState();HardwareKeyboard.instance.addHandler(_on);}
  @override void dispose(){HardwareKeyboard.instance.removeHandler(_on);super.dispose();}
  @override Widget build(BuildContext context)=>const SizedBox.shrink();
}
