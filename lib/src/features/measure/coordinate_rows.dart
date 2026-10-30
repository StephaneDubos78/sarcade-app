/// Presentation of the coordinate formats shared by the fiche « Infos du
/// point » and the convertisseur (lot 5, 30 Oct 2026): one line per format,
/// copied on a tap, with « Lecture radio » (NATO alphabet) and
/// « Grands caractères » to dictate it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import 'coordinates.dart';
import 'radio_spelling.dart';

/// Formats of the fiche « Infos du point » (validated mock-up).
const infoFormats=[CoordFormat.dd,CoordFormat.dms,CoordFormat.mgrs,CoordFormat.utm,CoordFormat.qth];
/// Formats of the converter: every one, in reading order.
const converterFormats=[CoordFormat.dd,CoordFormat.dm,CoordFormat.dms,CoordFormat.utm,CoordFormat.mgrs,CoordFormat.qth,CoordFormat.l93,CoordFormat.dfci];

String formatLabel(CoordFormat f)=>S.t('measure.format.${f.name}');

/// « Degrés décimaux : 48,80123 N · 2,13456 E », one per line.
String coordinatesText(LatLng p,List<CoordFormat> formats,{int mgrsDigits=4})=>
  [for(final f in formats)'${formatLabel(f)} : ${formatCoordinates(p,f,mgrsDigits:mgrsDigits)}'].join('\n');

void copyText(BuildContext context,String text){
  Clipboard.setData(ClipboardData(text:text));
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content:Text(S.t('common.copied')),duration:const Duration(seconds:2)));
}

/// Full screen value in big characters, with its radio reading.
Future<void> showBigValue(BuildContext context,String label,String value)=>showDialog<void>(context:context,builder:(c){
  final t=Theme.of(c);
  return Dialog.fullscreen(child:SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Expanded(child:Text(label,style:t.textTheme.titleLarge)),
      IconButton(tooltip:S.t('common.close'),onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close))]),
    Expanded(child:Center(child:FittedBox(fit:BoxFit.scaleDown,child:SelectableText(value.replaceAll(' · ','\n'),textAlign:TextAlign.center,
      style:const TextStyle(fontSize:64,fontWeight:FontWeight.w700,fontFeatures:[FontFeature.tabularFigures()],height:1.2))))),
    Text(radioSpelling(value,lang:S.lang),textAlign:TextAlign.center,style:t.textTheme.titleMedium?.copyWith(color:t.colorScheme.onSurfaceVariant)),
  ]))));
});

/// One labelled value: tap copies; optional radio reading and big text.
class InfoRow extends StatefulWidget {
  final String label, value; final IconData? icon; final bool spell;
  const InfoRow({super.key,required this.label,required this.value,this.icon,this.spell=false});
  @override State<InfoRow> createState()=>_InfoRowState();
}

class _InfoRowState extends State<InfoRow> {
  bool _reading=false;
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final s=t.colorScheme;
    final usable=widget.value.isNotEmpty&&widget.value!='—';
    return InkWell(onTap:usable?()=>copyText(context,widget.value):null,child:Padding(
      padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        if(widget.icon!=null)...[Icon(widget.icon,size:18,color:s.onSurfaceVariant),const SizedBox(width:10)],
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.label,style:t.textTheme.labelMedium?.copyWith(color:s.onSurfaceVariant)),
          Text(widget.value,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600,fontFeatures:[FontFeature.tabularFigures()])),
          if(_reading&&usable)Padding(padding:const EdgeInsets.only(top:2),child:Text(radioSpelling(widget.value,lang:S.lang),
            style:t.textTheme.bodySmall?.copyWith(color:s.primary))),
        ])),
        if(widget.spell&&usable)...[
          IconButton(tooltip:S.t('info.radio'),visualDensity:VisualDensity.compact,isSelected:_reading,
            onPressed:()=>setState(()=>_reading=!_reading),icon:const Icon(Icons.record_voice_over_outlined),selectedIcon:const Icon(Icons.record_voice_over)),
          IconButton(tooltip:S.t('info.big'),visualDensity:VisualDensity.compact,
            onPressed:()=>showBigValue(context,widget.label,widget.value),icon:const Icon(Icons.text_fields)),
        ],
        if(usable)Icon(Icons.copy_outlined,size:16,color:s.onSurfaceVariant),
      ])));
  }
}

/// Titled block of rows, in a card.
class InfoBlock extends StatelessWidget {
  final String title; final List<Widget> children; final Widget? trailing;
  const InfoBlock({super.key,required this.title,required this.children,this.trailing});
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    return Padding(padding:const EdgeInsets.only(bottom:12),child:Card(elevation:0,margin:EdgeInsets.zero,color:t.colorScheme.surfaceContainerLow,
      child:Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.fromLTRB(12,4,4,2),child:Row(children:[
          Expanded(child:Text(title,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w700))),if(trailing!=null)trailing!])),
        ...children,
      ]))));
  }
}

/// The coordinate formats of [point] as rows (shared presentation).
List<Widget> coordinateRows(LatLng point,List<CoordFormat> formats,{int mgrsDigits=4})=>[
  for(final f in formats)InfoRow(key:ValueKey('coord-${f.name}'),label:formatLabel(f),value:formatCoordinates(point,f,mgrsDigits:mgrsDigits),spell:true),
];
