/// Legend of the bearings on the map (card « Écran TV, étiquettes des
/// relevés trop grosses », decision of 30 Oct 2026, 2 h 36), application
/// part: compact, bottom left, shown only when bearings are visible,
/// foldable; open by default on a computer, a « Légende » button on a
/// phone. One line per search: a stroke of its colour and the signal,
/// EXERCICE badge kept.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'bearing_models.dart';

/// Searches shown, in a stable order, with their colour and exercise flag.
List<({String search,int color,bool exercise})> legendEntries(Iterable<Bearing> bearings){
  final by=<String,bool>{};
  for(final b in bearings){by[b.search]=(by[b.search]??false)||b.exercise;}
  final keys=by.keys.toList()..sort();
  return [for(final k in keys)(search:k,color:searchColor(k),exercise:by[k]!)];
}

class BearingLegend extends StatelessWidget {
  final Iterable<Bearing> bearings; final bool open; final ValueChanged<bool> onOpen;
  const BearingLegend({super.key,required this.bearings,required this.open,required this.onOpen});
  @override Widget build(BuildContext context){
    final entries=legendEntries(bearings);
    if(entries.isEmpty)return const SizedBox.shrink();
    final s=Theme.of(context).colorScheme;
    if(!open){
      return ActionChip(key:const ValueKey('legend-open'),avatar:const Icon(Icons.legend_toggle,size:18),label:Text(S.t('legend.title')),
        onPressed:()=>onOpen(true),backgroundColor:s.surface.withValues(alpha:0.92));
    }
    return Material(key:const ValueKey('legend'),color:s.surface.withValues(alpha:0.92),elevation:2,borderRadius:BorderRadius.circular(10),
      child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:260,maxHeight:180),child:Padding(padding:const EdgeInsets.fromLTRB(10,4,2,6),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(mainAxisSize:MainAxisSize.min,children:[
            Text(S.t('legend.title'),style:Theme.of(context).textTheme.labelMedium),const SizedBox(width:4),
            IconButton(key:const ValueKey('legend-close'),tooltip:S.t('legend.fold'),visualDensity:VisualDensity.compact,iconSize:18,
              onPressed:()=>onOpen(false),icon:const Icon(Icons.expand_more)),
          ]),
          Flexible(child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
            for(final e in entries)Padding(padding:const EdgeInsets.only(bottom:3,right:8),child:Row(mainAxisSize:MainAxisSize.min,children:[
              Container(width:18,height:3,color:Color(e.color)),const SizedBox(width:6),
              Flexible(child:Text(e.search.isEmpty?S.t('legend.noSignal'):e.search,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12))),
              if(e.exercise)...[const SizedBox(width:6),Container(padding:const EdgeInsets.symmetric(horizontal:4),
                decoration:BoxDecoration(color:Colors.amber.shade700,borderRadius:BorderRadius.circular(3)),
                child:const Text('EXERCICE',style:TextStyle(fontSize:9,fontWeight:FontWeight.w800,color:Colors.black)))],
            ])),
          ]))),
        ]))));
  }
}
