/// « Ouvrir » en fenêtre superposée façon Google Play Console (validated on
/// 30 Oct 2026, 2 h 17): a sub-page opened from Paramètres is a window laid
/// over it — its title and a cross at the top, the page behind darkened,
/// Échap or a click outside closes it. On a phone, a sheet rising from the
/// bottom over about 90 % of the screen. The sub-page keeps its own bar
/// (title, actions); its back arrow becomes the cross.
library;

import 'package:flutter/material.dart';

Future<T?> showOverlayPage<T>(BuildContext context,WidgetBuilder builder){
  Widget page(BuildContext c)=>ActionIconTheme(
    data:ActionIconThemeData(backButtonIconBuilder:(_)=>const Icon(Icons.close)),
    child:Builder(builder:builder));
  final size=MediaQuery.sizeOf(context);
  if(size.width<700){
    return showModalBottomSheet<T>(context:context,isScrollControlled:true,useSafeArea:true,showDragHandle:false,
      clipBehavior:Clip.antiAlias,
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      builder:(c)=>SizedBox(height:MediaQuery.sizeOf(c).height*0.9,child:page(c)));
  }
  return showDialog<T>(context:context,barrierDismissible:true,barrierColor:Colors.black54,
    builder:(c)=>Dialog(clipBehavior:Clip.antiAlias,insetPadding:const EdgeInsets.all(32),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
      child:ConstrainedBox(constraints:BoxConstraints(maxWidth:960,maxHeight:MediaQuery.sizeOf(c).height*0.9),
        child:SizedBox(width:960,height:MediaQuery.sizeOf(c).height*0.9,child:page(c)))));
}
