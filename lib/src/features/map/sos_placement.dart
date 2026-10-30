import 'package:flutter/widgets.dart';

/// Place of the SOS button on a phone (card « Détresse encore dans le menu
/// Plus », 30 Oct 2026): always on the map, bottom left; at mid-height on
/// the left edge while a bearing sheet or a station card covers the bottom.
Widget sosPlacement({required bool taking,required bool card,required Widget child})=>taking||card
  ?Positioned(left:12,top:0,bottom:0,child:Center(child:child))
  :Positioned(left:12,bottom:100,child:child);
