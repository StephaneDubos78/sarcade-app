import 'package:flutter/widgets.dart';

/// Width of the bearing sheet opened on the right of a computer or a
/// tablet (« Relevé » with the arrow).
const double bearingSheetWidth=380;

/// Place of the right column of the map (« Fond et affichage », position,
/// Écrans, SOS at the bottom; decision of 30 Oct 2026, 3 h 05). SOS is never
/// hidden by a panel (revue d'ergonomie n° 15, 18, 32):
/// - phone, while a bearing sheet, a station card, the measure card or the
///   navigation card covers the bottom: mid-height on the right edge;
/// - computer and tablet, while the bearing sheet is open on the right:
///   the column moves to its left, at the same height;
/// - otherwise bottom right.
Widget mapColumnPlacement({required bool compact,required bool taking,required bool card,required double bottom,required Widget child,
    bool panel=false,double rightSheet=0})=>
  compact&&(taking||card||panel)
    ?Positioned(right:12,top:0,bottom:0,child:Center(child:child))
    :Positioned(right:rightSheet>0?12+rightSheet+12:12,bottom:bottom,child:child);

/// Phone, map under the floating tab bar: the map stops at the top of the
/// bar so that nothing it draws (labels, markers) is hidden behind it
/// (revue n° 2); the bar keeps floating over the background.
Widget mapBottomMargin(BuildContext context,{required bool fullBleed,required Widget child}){
  if(!fullBleed)return child;
  final bottom=MediaQuery.paddingOf(context).bottom;
  return Padding(padding:EdgeInsets.only(bottom:bottom),
    child:MediaQuery.removePadding(context:context,removeBottom:true,child:child));
}

/// Phone: the ⓘ of the base map sits above « Suivi actif » (bottom left).
const double mapAttributionLift=52;

/// The scale sits just above the ⓘ of the base map (bottom left).
double mapScaleBottom({required bool compact})=>compact?mapAttributionLift+44:44;
