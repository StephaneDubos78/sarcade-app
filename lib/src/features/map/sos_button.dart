/// Bouton SOS sur la carte (decision of 29 Oct 2026, 12 h 14): a small round
/// red button for every operator, held 2 s to send the distress (no alert
/// from a stray touch in a pocket); while in distress it becomes « Fin de
/// détresse », blinking.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';

class SosButton extends StatefulWidget {
  final bool inDistress;
  final VoidCallback onTriggered, onEnd;
  final Duration hold;
  const SosButton({super.key,required this.inDistress,required this.onTriggered,required this.onEnd,this.hold=const Duration(seconds:2)});
  @override State<SosButton> createState()=>_SosButtonState();
}

class _SosButtonState extends State<SosButton> with TickerProviderStateMixin {
  late final AnimationController _progress=AnimationController(vsync:this,duration:widget.hold)
    ..addStatusListener((s){if(s==AnimationStatus.completed){_down=null;_progress.reset();HapticFeedback.heavyImpact();widget.onTriggered();}});
  late final AnimationController _blink=AnimationController(vsync:this,duration:const Duration(milliseconds:700));

  @override void initState(){super.initState();_syncBlink();}
  @override void didUpdateWidget(SosButton old){super.didUpdateWidget(old);_syncBlink();}
  void _syncBlink(){if(widget.inDistress){if(!_blink.isAnimating)_blink.repeat(reverse:true);}else{_blink.stop();_blink.value=0;}}
  Offset? _down;
  void _cancel(){_down=null;if(_progress.isAnimating)_progress.reset();}
  @override void dispose(){_progress.dispose();_blink.dispose();super.dispose();}

  @override
  Widget build(BuildContext context){
    const red=Color(0xFFD93025);
    if(widget.inDistress){
      return FadeTransition(opacity:Tween(begin:1.0,end:0.45).animate(_blink),child:Material(color:red,shape:const StadiumBorder(),elevation:4,
        child:InkWell(customBorder:const StadiumBorder(),onTap:widget.onEnd,child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.sos,color:Colors.white),const SizedBox(width:6),
            Text(S.t('distress.end'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),
          ])))));
    }
    // Raw pointer events (29 Oct 2026): a GestureDetector tap lost the arena
    // to the Tooltip long press after 0.5 s, so the 2 s hold never ended
    // (web and touch). The Listener stays out of the gesture arena.
    return Semantics(button:true,label:S.t('distress.title'),hint:S.t('distress.holdTooltip'),
      child:Listener(behavior:HitTestBehavior.opaque,
        onPointerDown:(e){_down=e.position;_progress.forward(from:0);},
        onPointerMove:(e){if(_down!=null&&(e.position-_down!).distance>24)_cancel();},
        // Released too early: say how to send it (the tooltip was the only hint).
        onPointerUp:(_){final early=_progress.isAnimating;_cancel();
          if(early)ScaffoldMessenger.maybeOf(context)?..hideCurrentSnackBar()..showSnackBar(SnackBar(content:Text(S.t('distress.holdTooltip'))));},
        onPointerCancel:(_)=>_cancel(),
        child:SizedBox(width:56,height:56,child:Stack(alignment:Alignment.center,children:[
          AnimatedBuilder(animation:_progress,builder:(context,child)=>SizedBox(width:56,height:56,
            child:CircularProgressIndicator(value:_progress.value,strokeWidth:4,color:red,backgroundColor:Colors.transparent))),
          Container(width:46,height:46,alignment:Alignment.center,
            decoration:const BoxDecoration(color:red,shape:BoxShape.circle,boxShadow:[BoxShadow(blurRadius:6,color:Color(0x55000000))]),
            child:const Text('SOS',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:14,letterSpacing:0.5))),
        ]))));
  }
}
