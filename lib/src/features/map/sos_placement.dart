import 'package:flutter/widgets.dart';

/// Place of the right column of the map (« Fond et affichage », position,
/// SOS at the bottom; decision of 30 Oct 2026, 3 h 05): bottom right; at
/// mid-height on the right edge on a phone while a bearing sheet or a
/// station card covers the bottom, so that SOS stays in sight.
Widget mapColumnPlacement({required bool compact,required bool taking,required bool card,required double bottom,required Widget child})=>
  compact&&(taking||card)
    ?Positioned(right:12,top:0,bottom:0,child:Center(child:child))
    :Positioned(right:12,bottom:bottom,child:child);
