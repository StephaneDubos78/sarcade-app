import '../../../l10n/strings.dart';
import 'package:flutter/material.dart';

import 'drawing_controller.dart';
import 'geometry.dart';
import 'map_feature.dart';

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
  _=>S.t('draw.hint.line'),
};

/// Compact drawing toolbar: the nine tools, undo/redo, export and close.
class DrawingToolbar extends StatelessWidget {
  final DrawingController controller;
  final VoidCallback onClose, onExport, onImport;
  const DrawingToolbar({super.key,required this.controller,required this.onClose,required this.onExport,required this.onImport});

  @override
  Widget build(BuildContext context){
    final c=controller;
    final scheme=Theme.of(context).colorScheme;
    return Material(
      elevation:4,borderRadius:BorderRadius.circular(14),color:scheme.surface,
      child:SingleChildScrollView(
        scrollDirection:Axis.horizontal,
        padding:const EdgeInsets.symmetric(horizontal:4,vertical:4),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          for(final k in FeatureKind.values)Padding(
            padding:const EdgeInsets.symmetric(horizontal:2),
            child:_ToolButton(kind:k,active:c.tool==k,onTap:()=>c.selectTool(c.tool==k?null:k)),
          ),
          const SizedBox(height:40,child:VerticalDivider(width:12)),
          IconButton(tooltip:S.t('draw.undo'),onPressed:c.canUndo?c.undo:null,icon:const Icon(Icons.undo)),
          IconButton(tooltip:S.t('draw.redo'),onPressed:c.canRedo?c.redo:null,icon:const Icon(Icons.redo)),
          IconButton(tooltip:S.t('draw.import'),onPressed:onImport,icon:const Icon(Icons.file_upload_outlined)),
          IconButton(tooltip:S.t('draw.export'),onPressed:c.features.isEmpty?null:onExport,icon:const Icon(Icons.file_download_outlined)),
          IconButton(tooltip:S.t('draw.close'),onPressed:onClose,icon:const Icon(Icons.close)),
        ]),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final FeatureKind kind; final bool active; final VoidCallback onTap;
  const _ToolButton({required this.kind,required this.active,required this.onTap});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    return Tooltip(message:kind.label,child:InkWell(
      borderRadius:BorderRadius.circular(10),onTap:onTap,
      child:Container(
        width:54,padding:const EdgeInsets.symmetric(vertical:4),
        decoration:BoxDecoration(color:active?scheme.primaryContainer:null,borderRadius:BorderRadius.circular(10)),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Icon(toolIcon(kind),color:active?scheme.onPrimaryContainer:scheme.onSurface),
          const SizedBox(height:2),
          Text(kind.label,style:TextStyle(fontSize:11,fontWeight:active?FontWeight.bold:FontWeight.normal,color:active?scheme.onPrimaryContainer:scheme.onSurfaceVariant)),
        ]),
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
          if(t.isMultiVertex)IconButton(tooltip:S.t('closures.finish'),onPressed:c.canFinish?c.finish:null,icon:const Icon(Icons.check_circle),color:Colors.lightGreenAccent,disabledColor:Colors.white24),
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
  const SelectionBar({super.key,required this.controller,required this.onEditLabel});

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
            [f.kind.label,if(f.label.isNotEmpty&&f.kind!=FeatureKind.text)f.label,?info].join(' · '),
            maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.labelLarge,
          )),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(mainAxisSize:MainAxisSize.min,children:[
            PopupMenuButton<int>(
              tooltip:S.t('groups.color'),onSelected:c.setColor,
              itemBuilder:(_)=>[for(final col in drawingPalette)PopupMenuItem(value:col,child:Row(children:[Icon(Icons.circle,color:Color(col)),if(col==f.color)const Padding(padding:EdgeInsets.only(left:8),child:Icon(Icons.check,size:18))]))],
              child:Padding(padding:const EdgeInsets.all(10),child:Icon(Icons.circle,color:Color(f.color),size:26)),
            ),
            if(f.kind!=FeatureKind.point&&f.kind!=FeatureKind.text)PopupMenuButton<double>(
              tooltip:S.t('draw.width'),onSelected:c.setStrokeWidth,
              itemBuilder:(_)=>[for(final w in drawingWidths)PopupMenuItem(value:w,child:Row(children:[SizedBox(width:48,child:Divider(thickness:w,color:Colors.black87)),const SizedBox(width:10),Text(w==drawingWidths.first?'Fin':w==drawingWidths.last?'Épais':'Moyen')]))],
              child:const Padding(padding:EdgeInsets.all(10),child:Icon(Icons.line_weight)),
            ),
            IconButton(tooltip:f.kind==FeatureKind.text?S.t('draw.editText'):S.t('groups.name'),onPressed:onEditLabel,icon:const Icon(Icons.edit_outlined)),
            IconButton(tooltip:S.t('draw.duplicate'),onPressed:c.duplicateSelected,icon:const Icon(Icons.copy_all_outlined)),
            IconButton(tooltip:S.t('routes.delete'),onPressed:c.deleteSelected,icon:const Icon(Icons.delete_outline),color:Colors.red.shade700),
            IconButton(tooltip:S.t('draw.deselect'),onPressed:()=>c.select(null),icon:const Icon(Icons.close)),
          ])),
        ]),
      ),
    );
  }
}
