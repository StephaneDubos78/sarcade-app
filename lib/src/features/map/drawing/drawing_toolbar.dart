import '../../../l10n/strings.dart';
import 'package:flutter/material.dart';

import 'drawing_controller.dart';
import 'geometry.dart';
import 'map_feature.dart';
import 'multi_select.dart';
import '../../../ui/color_palette.dart';

IconData toolIcon(FeatureKind k)=>switch(k){
  FeatureKind.point=>Icons.place_outlined,
  FeatureKind.line=>Icons.timeline,
  FeatureKind.arrow=>Icons.north_east,
  FeatureKind.circle=>Icons.circle_outlined,
  FeatureKind.rectangle=>Icons.crop_square,
  FeatureKind.zone=>Icons.pentagon_outlined,
  FeatureKind.text=>Icons.text_fields,
  FeatureKind.freehand=>Icons.gesture,
  FeatureKind.measure=>Icons.straighten,
};

String toolHint(FeatureKind k)=>switch(k){
  FeatureKind.point=>S.t('draw.hint.point'),
  FeatureKind.text=>S.t('draw.hint.text'),
  FeatureKind.circle=>S.t('draw.hint.circle'),
  FeatureKind.rectangle=>S.t('draw.hint.rectangle'),
  FeatureKind.freehand=>S.t('draw.hint.freehand'),
  FeatureKind.zone=>S.t('draw.hint.zone'),
  FeatureKind.arrow=>S.t('draw.hint.arrow'),
  _=>S.t('draw.hint.line'),
};

/// Tools of the drawing toolbar: no « Mesure » (card « Barre de dessin,
/// retirer Mesure », 30 Oct 2026, 13 h 28: « Mesurer jusqu'ici » of the
/// point menu does it; the measures already saved stay editable).
final drawingToolbarKinds=[for(final k in FeatureKind.values)if(k!=FeatureKind.measure)k];

/// Same width for every tool button, fitted to the longest label on one line
/// (card « Barre de dessin iPhone, libellé Rectangle coupé », 13 h 21).
double toolButtonWidth(BuildContext context,Iterable<String> labels){
  final scaler=MediaQuery.textScalerOf(context);
  var w=0.0;
  for(final l in labels){
    final tp=TextPainter(text:TextSpan(text:l,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold)),textDirection:TextDirection.ltr,maxLines:1,textScaler:scaler)..layout();
    if(tp.width>w)w=tp.width;
  }
  return (w+12).clamp(54.0,84.0).ceilToDouble();
}

/// Compact drawing toolbar: drawing tools only, selection, undo/redo and
/// close (import and export moved to Plus › Fichiers, card of 13 h 27).
class DrawingToolbar extends StatelessWidget {
  final DrawingController controller;
  final VoidCallback onClose;
  const DrawingToolbar({super.key,required this.controller,required this.onClose});

  @override
  Widget build(BuildContext context){
    final c=controller;
    final scheme=Theme.of(context).colorScheme;
    final width=toolButtonWidth(context,[for(final k in drawingToolbarKinds)k.label]);
    final tools=<Widget>[
      for(final k in drawingToolbarKinds)Padding(
        padding:const EdgeInsets.symmetric(horizontal:2),
        child:_ToolButton(key:ValueKey('draw-tool-${k.name}'),kind:k,active:c.tool==k,width:width,onTap:()=>c.selectTool(c.tool==k?null:k)),
      ),
      // « Sélection » left the drawing bar (17 h 36): long press on an
      // object, or « Sélectionner une zone » of the point menu.
    ];
    final undo=IconButton(tooltip:S.t('draw.undo'),onPressed:c.canUndo?c.undo:null,icon:const Icon(Icons.undo));
    final redo=IconButton(tooltip:S.t('draw.redo'),onPressed:c.canRedo?c.redo:null,icon:const Icon(Icons.redo));
    final close=IconButton(key:const ValueKey('draw-close'),tooltip:S.t('draw.close'),onPressed:onClose,icon:const Icon(Icons.close));
    // Phone (revue d'ergonomie n° 21): the tools on two rows, nothing hidden
    // behind a scroll; « Fermer » and « Annuler » always in sight on the right.
    if(drawingToolbarWraps(MediaQuery.sizeOf(context).width)){
      return Material(elevation:4,borderRadius:BorderRadius.circular(14),color:scheme.surface,
        child:Padding(padding:const EdgeInsets.all(4),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:Wrap(runSpacing:4,children:[...tools,redo])),
          Column(mainAxisSize:MainAxisSize.min,children:[close,undo]),
        ])));
    }
    return Material(
      elevation:4,borderRadius:BorderRadius.circular(14),color:scheme.surface,
      child:SingleChildScrollView(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:4,vertical:4),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          ...tools,
          const SizedBox(height:40,child:VerticalDivider(width:12)),
          undo,redo,close,
        ]),
      ),
    );
  }
}

/// Phone width: the drawing toolbar wraps on two rows.
bool drawingToolbarWraps(double screenWidth)=>screenWidth<600;

/// Icon and label of a tool button: label on one line, never cut (scaled
/// down if needed), icons on the same line for every button.
Widget _toolFace(IconData icon,String label,bool active,ColorScheme scheme)=>Column(mainAxisSize:MainAxisSize.min,children:[
  Icon(icon,color:active?scheme.onPrimaryContainer:scheme.onSurface),
  const SizedBox(height:2),
  SizedBox(height:15,child:FittedBox(fit:BoxFit.scaleDown,child:Text(label,maxLines:1,softWrap:false,
    style:TextStyle(fontSize:11,fontWeight:active?FontWeight.bold:FontWeight.normal,color:active?scheme.onPrimaryContainer:scheme.onSurfaceVariant)))),
]);

class _ToolButton extends StatelessWidget {
  final FeatureKind kind; final bool active; final double width; final VoidCallback onTap;
  const _ToolButton({super.key,required this.kind,required this.active,required this.width,required this.onTap});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    return Tooltip(message:kind.label,child:InkWell(
      // The tooltip goes away with the click (revue n° 23).
      borderRadius:BorderRadius.circular(10),onTap:(){Tooltip.dismissAllToolTips();onTap();},
      child:Container(
        width:width,padding:const EdgeInsets.symmetric(vertical:4),
        decoration:BoxDecoration(color:active?scheme.primaryContainer:null,borderRadius:BorderRadius.circular(10)),
        child:_toolFace(toolIcon(kind),kind.label,active,scheme),
      ),
    ));
  }
}

/// Status line while a tool is active: hint, live measure, and the actions
/// to remove the last vertex, finish or cancel.
class DraftBar extends StatelessWidget {
  final DrawingController controller;
  const DraftBar({super.key,required this.controller});
  @override Widget build(BuildContext context){
    final c=controller, t=c.tool;
    if(t==null)return const SizedBox.shrink();
    final measure=c.draftMeasure;
    final count=c.draft.length;
    return Material(
      elevation:3,borderRadius:BorderRadius.circular(12),color:Theme.of(context).colorScheme.inverseSurface,
      child:Padding(
        padding:const EdgeInsets.fromLTRB(14,4,4,4),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(toolIcon(t),size:18,color:Theme.of(context).colorScheme.onInverseSurface),
          const SizedBox(width:8),
          Flexible(child:Text(
            [t.isMultiVertex&&count>0?S.t('draw.points',{'n':count}):toolHint(t),?measure].join(' · '),
            maxLines:2,overflow:TextOverflow.ellipsis,
            style:TextStyle(color:Theme.of(context).colorScheme.onInverseSurface),
          )),
          if(t.isMultiVertex&&count>0)IconButton(tooltip:S.t('draw.removeLast'),onPressed:c.undoLastVertex,icon:const Icon(Icons.backspace_outlined),color:Theme.of(context).colorScheme.onInverseSurface),
          if(t.isMultiVertex)IconButton(tooltip:S.t('closures.finish'),onPressed:c.canFinish?c.finish:null,icon:const Icon(Icons.check_circle),color:Colors.white,disabledColor:Colors.white60),
          IconButton(tooltip:S.t('draw.cancel'),onPressed:()=>c.selectTool(null),icon:const Icon(Icons.close),color:Theme.of(context).colorScheme.onInverseSurface),
        ]),
      ),
    );
  }
}

/// PowerPoint-style mini toolbar for the selected object.
class SelectionBar extends StatelessWidget {
  final DrawingController controller;
  final Future<void> Function() onEditLabel;
  /// PCO: a closed shape can become a géorepérage.
  final bool canFence;
  const SelectionBar({super.key,required this.controller,required this.onEditLabel,this.canFence=false});

  String? _info(MapFeature f){
    if(f.kind==FeatureKind.circle)return '${S.t('draw.radius')} ${formatDistance(f.radiusM??0)} · ${formatArea(f.areaM2)}';
    if(f.isClosed)return formatArea(f.areaM2);
    if(f.kind.isLinear)return formatDistance(f.lengthM);
    return null;
  }

  @override Widget build(BuildContext context){
    final c=controller, f=c.selected;
    if(f==null)return const SizedBox.shrink();
    final info=_info(f);
    return Material(
      elevation:4,borderRadius:BorderRadius.circular(14),color:Theme.of(context).colorScheme.surface,
      child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Padding(padding:const EdgeInsets.fromLTRB(8,6,8,0),child:Text(
            [f.kind.label,if(f.label.isNotEmpty&&f.kind!=FeatureKind.text)f.label,?info,if(f.geofence)S.t('draw.geofence')].join(' · '),
            maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.labelLarge,
          )),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(mainAxisSize:MainAxisSize.min,children:[
            ColorPaletteButton(color:f.color,colors:paletteWith(f.color),onSelected:c.setColor),
            if(f.kind!=FeatureKind.point&&f.kind!=FeatureKind.text)PopupMenuButton<double>(
              tooltip:S.t('draw.width'),onSelected:c.setStrokeWidth,
              itemBuilder:(_)=>[for(final w in drawingWidths)PopupMenuItem(value:w,child:Row(children:[SizedBox(width:48,child:Divider(thickness:w,color:Colors.black87)),const SizedBox(width:10),Text(w==drawingWidths.first?'Fin':w==drawingWidths.last?'Épais':'Moyen')]))],
              child:const Padding(padding:EdgeInsets.all(10),child:Icon(Icons.line_weight)),
            ),
            PopupMenuButton<double>(
              tooltip:S.t('draw.opacity'),onSelected:c.setOpacity,
              itemBuilder:(_)=>[for(final o in drawingOpacities)CheckedPopupMenuItem(value:o,checked:(f.opacity-o).abs()<0.01,child:Text('${(o*100).round()} %'))],
              child:Padding(padding:const EdgeInsets.all(10),child:Icon(Icons.opacity,color:Color(f.color).withValues(alpha:f.opacity))),
            ),
            if(f.kind==FeatureKind.text)fontSizeButton(c,f),
            IconButton(tooltip:f.kind==FeatureKind.text?S.t('draw.editText'):S.t('groups.name'),onPressed:onEditLabel,icon:const Icon(Icons.edit_outlined)),
            // Géorepérage (PCO): alert when a team enters or leaves the zone.
            if(f.isClosed&&canFence)IconButton(tooltip:S.t(f.geofence?'draw.geofenceOff':'draw.geofenceOn'),onPressed:c.toggleGeofence,
              isSelected:f.geofence,icon:Icon(f.geofence?Icons.notifications_active:Icons.notifications_none_outlined)),
            IconButton(tooltip:S.t('draw.duplicate'),onPressed:c.duplicateSelected,icon:const Icon(Icons.copy_all_outlined)),
            IconButton(tooltip:S.t('routes.delete'),onPressed:c.deleteSelected,icon:const Icon(Icons.delete_outline),color:Colors.red.shade700),
            IconButton(tooltip:S.t('draw.deselect'),onPressed:c.endSelection,icon:const Icon(Icons.close)),
          ])),
        ]),
      ),
    );
  }
}

/// Selection mode with nothing selected yet: what to do, and ✕.
class SelectionHint extends StatelessWidget {
  final DrawingController controller;
  const SelectionHint({super.key,required this.controller});
  @override Widget build(BuildContext context)=>Material(key:const ValueKey('selection-hint'),elevation:4,borderRadius:BorderRadius.circular(14),
    color:Theme.of(context).colorScheme.surface,child:Padding(padding:const EdgeInsets.fromLTRB(14,4,4,4),child:Row(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.highlight_alt),const SizedBox(width:8),
      Flexible(child:Text(S.t('draw.selectHint'))),
      IconButton(tooltip:S.t('common.cancel'),onPressed:controller.endSelection,icon:const Icon(Icons.close)),
    ])));
}
