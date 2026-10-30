/// Weather pill with the link dot (card « Téléphone, carte en portrait »,
/// decision of 30 Oct 2026, 1 h 30, same design on phones, web and
/// Windows): « ● ☀ 6° · E 11 km/h ». The « Connecté » pill is gone; a touch
/// on the dot opens the links, the rest the weather; « ● Coupée » when the
/// link is slowed or cut.
library;

import 'package:flutter/material.dart';

/// Height shared by the pills of the top bar (card « Carte web, barre du
/// haut, finitions », 1 h 02).
const pillHeight=40.0;

class LinkWeatherPill extends StatelessWidget {
  final Color dot; final String linkTooltip; final String? linkWord;
  final IconData? weatherIcon; final String? weatherText; final Color? alert;
  final VoidCallback onLinks; final VoidCallback onWeather;
  const LinkWeatherPill({super.key,required this.dot,required this.linkTooltip,required this.onLinks,required this.onWeather,
    this.linkWord,this.weatherIcon,this.weatherText,this.alert});

  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    final weather=weatherText!=null;
    final r=BorderRadius.circular(pillHeight/2);
    return Container(height:pillHeight,
      decoration:BoxDecoration(color:alert??s.surface.withValues(alpha:0.92),borderRadius:r,border:Border.all(color:s.outline)),
      child:Material(color:Colors.transparent,borderRadius:r,clipBehavior:Clip.antiAlias,child:Row(mainAxisSize:MainAxisSize.min,children:[
        Tooltip(message:linkTooltip,child:InkWell(onTap:onLinks,child:Padding(
          padding:EdgeInsets.only(left:14,right:weather?6:14),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            Container(width:10,height:10,decoration:BoxDecoration(color:dot,shape:BoxShape.circle)),
            if(linkWord!=null)...[const SizedBox(width:6),Text(linkWord!,style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:s.onSurface))],
          ])))),
        if(weather)InkWell(onTap:onWeather,child:Padding(padding:const EdgeInsets.only(left:6,right:14),child:Row(mainAxisSize:MainAxisSize.min,children:[
          if(weatherIcon!=null)...[Icon(weatherIcon,size:16),const SizedBox(width:4)],
          Text(weatherText!,style:const TextStyle(fontSize:13)),
        ]))),
      ])));
  }
}
