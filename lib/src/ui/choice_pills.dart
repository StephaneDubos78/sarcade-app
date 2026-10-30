/// « Choix multiples sans bordures noires » (validated on 30 Oct 2026,
/// 2 h 14): every segmented choice of the application is a row of rounded
/// pills without border, in the style of « Tester le réveil »: the chosen one
/// light blue with a check mark, the others light grey.
library;

import 'package:flutter/material.dart';

typedef PillChoice<T>=({T value,String label,IconData? icon});

class ChoicePills<T> extends StatelessWidget {
  final List<PillChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool compact;
  const ChoicePills({super.key,required this.choices,required this.selected,required this.onSelected,this.compact=false});

  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Wrap(spacing:8,runSpacing:8,children:[for(final c in choices)Builder(builder:(_){
      final on=c.value==selected;
      final fg=on?s.onPrimaryContainer:s.onSurface;
      return Semantics(button:true,selected:on,inMutuallyExclusiveGroup:true,child:Material(
        color:on?s.primaryContainer:s.surfaceContainerHighest,shape:const StadiumBorder(),clipBehavior:Clip.antiAlias,
        child:InkWell(onTap:on?null:()=>onSelected(c.value),child:Padding(
          padding:EdgeInsets.symmetric(horizontal:compact?12:16,vertical:compact?6:9),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            if(on)Icon(Icons.check,size:18,color:fg) else if(c.icon!=null)Icon(c.icon,size:18,color:fg),
            if(on||c.icon!=null)const SizedBox(width:6),
            Text(c.label,style:TextStyle(color:fg,fontWeight:on?FontWeight.w600:FontWeight.w500)),
          ])))));
    })]);
  }
}
