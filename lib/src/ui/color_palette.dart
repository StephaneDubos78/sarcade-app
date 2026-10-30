import 'package:flutter/material.dart';

import '../features/map/drawing/drawing_controller.dart' show drawingPalette;
import '../l10n/strings.dart';

/// Shared colour palette (card « iPhone, choix de couleur d'un objet
/// dessiné », validated 30 Oct 2026, 13 h 25): a compact 4 × 4 grid, the
/// same everywhere (drawing, Profil, groups). Opened under the colour button
/// on a computer, as a low bottom sheet on a phone; closed when a colour is
/// picked, by Escape or by touching elsewhere.
const paletteColumns=4, paletteCellPx=34.0, paletteGapPx=8.0;
const phonePaletteWidth=600.0;

/// Width of the grid for [columns] cells.
double paletteGridWidth([int columns=paletteColumns])=>columns*paletteCellPx+(columns-1)*paletteGapPx;

/// [colors] with [extra] added at the end when it is not one of them.
List<int> paletteWith(int? extra,[List<int> colors=drawingPalette])=>[...colors,if(extra!=null&&!colors.contains(extra))extra];

/// Thin outline of a swatch, visible in both themes (revue d'ergonomie
/// n° 26: the black swatch vanished on the dark background): light on dark,
/// dark on light; a bit thicker for the black and white swatches.
({Color color,double width}) swatchOutline(int c,Brightness theme){
  final l=Color(c).computeLuminance();
  final edge=l<0.05||l>0.9;
  return (color:theme==Brightness.dark?Colors.white60:Colors.black38,width:edge?1.5:1);
}

class ColorGrid extends StatelessWidget {
  final List<int> colors; final int? selected; final ValueChanged<int> onPick;
  const ColorGrid({super.key,this.colors=drawingPalette,this.selected,required this.onPick});
  @override Widget build(BuildContext context){
    final primary=Theme.of(context).colorScheme.primary;
    return SizedBox(width:paletteGridWidth(),child:Wrap(spacing:paletteGapPx,runSpacing:paletteGapPx,children:[
      for(final c in colors)Semantics(label:S.t('color.$c'),selected:c==selected,button:true,child:InkWell(
        key:ValueKey('palette-$c'),customBorder:const CircleBorder(),onTap:()=>onPick(c),
        child:Container(width:paletteCellPx,height:paletteCellPx,
          decoration:BoxDecoration(color:Color(c),shape:BoxShape.circle,border:c==selected?Border.all(color:primary,width:3)
            :Border.all(color:swatchOutline(c,Theme.of(context).brightness).color,width:swatchOutline(c,Theme.of(context).brightness).width)),
          child:c==selected?Icon(Icons.check,size:18,color:Color(c).computeLuminance()>0.5?Colors.black:Colors.white):null),
      )),
    ]));
  }
}

/// Opens the palette for the button of [context]; returns the picked colour.
Future<int?> showColorPalette(BuildContext context,{int? selected,List<int> colors=drawingPalette}) async {
  final phone=MediaQuery.sizeOf(context).width<phonePaletteWidth;
  if(phone){
    return showModalBottomSheet<int>(context:context,showDragHandle:true,useSafeArea:true,
      builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,16),
        child:Center(heightFactor:1,child:ColorGrid(colors:colors,selected:selected,onPick:(c)=>Navigator.pop(ctx,c))))));
  }
  final box=context.findRenderObject() as RenderBox?;
  final overlay=Overlay.of(context).context.findRenderObject() as RenderBox?;
  if(box==null||overlay==null)return null;
  final topLeft=box.localToGlobal(Offset(0,box.size.height),ancestor:overlay);
  final position=RelativeRect.fromRect(Rect.fromLTWH(topLeft.dx,topLeft.dy,box.size.width,0),Offset.zero&overlay.size);
  return showMenu<int>(context:context,position:position,items:[_GridEntry(colors:colors,selected:selected)]);
}

class _GridEntry extends PopupMenuEntry<int> {
  final List<int> colors; final int? selected;
  const _GridEntry({required this.colors,required this.selected});
  @override double get height=>paletteGridWidth();
  @override bool represents(int? value)=>false;
  @override State<_GridEntry> createState()=>_GridEntryState();
}

class _GridEntryState extends State<_GridEntry> {
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(10),
    child:ColorGrid(colors:widget.colors,selected:widget.selected,onPick:(c)=>Navigator.pop(context,c)));
}

/// Round colour button that opens the palette.
class ColorPaletteButton extends StatelessWidget {
  final int color; final ValueChanged<int> onSelected; final List<int> colors;
  const ColorPaletteButton({super.key,required this.color,required this.onSelected,this.colors=drawingPalette});
  @override Widget build(BuildContext context)=>Tooltip(message:S.t('groups.color'),child:InkWell(
    key:const ValueKey('color-button'),customBorder:const CircleBorder(),
    onTap:() async {final c=await showColorPalette(context,selected:color,colors:colors);if(c!=null)onSelected(c);},
    child:Padding(padding:const EdgeInsets.all(10),child:Icon(Icons.circle,color:Color(color),size:26)),
  ));
}
