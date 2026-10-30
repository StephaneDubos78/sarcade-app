import 'dart:async';

import 'package:flutter/material.dart';

import 'locate_cycle.dart';

/// The single position button with its short label shown 2 s at each
/// change of mode (« Suivi », « Boussole », « Tous les opérateurs »).
class LocateButton extends StatefulWidget {
  final LocateMode mode; final Widget Function(String tooltip,Widget icon,bool active) fab;
  const LocateButton({super.key,required this.mode,required this.fab});
  @override State<LocateButton> createState()=>_LocateButtonState();
}

class _LocateButtonState extends State<LocateButton> {
  String? _label; Timer? _timer;
  @override void didUpdateWidget(LocateButton old){
    super.didUpdateWidget(old);
    if(old.mode==widget.mode)return;
    _timer?.cancel();
    _label=locateLabel(widget.mode);
    if(_label!=null)_timer=Timer(const Duration(seconds:2),(){if(mounted)setState(()=>_label=null);});
  }
  @override void dispose(){_timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme; final m=widget.mode;
    final active=m==LocateMode.follow||m==LocateMode.compass;
    return Row(mainAxisSize:MainAxisSize.min,children:[
      if(_label!=null)Container(margin:const EdgeInsets.only(right:8),padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
        decoration:BoxDecoration(color:s.inverseSurface,borderRadius:BorderRadius.circular(12)),
        child:Text(_label!,style:TextStyle(fontSize:13,color:s.onInverseSurface))),
      widget.fab(locateTooltip(m),Icon(locateIcon(m)),active),
    ]);
  }
}
