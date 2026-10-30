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

/// Touch area of the pill (revue d'ergonomie n° 7): 48 px high, the dot
/// part at least 48 px wide; the drawn pill stays 40 px.
const pillTouch=48.0;

/// Text of the weather part: « 14° · E 11 km/h » on tablets and computers,
/// the temperature alone on a phone (card « Téléphone, barre du haut
/// allégée », 30 Oct 2026, 17 h 43: the search gets the room back).
String? pillWeatherText({double? temperatureC,String? wind,required bool compact}){
  final parts=[if(temperatureC!=null)'${temperatureC.round()}°',if(!compact&&wind!=null&&wind.isNotEmpty)wind];
  return parts.isEmpty?null:parts.join(' · ');
}

class LinkWeatherPill extends StatelessWidget {
  final Color dot; final String linkTooltip; final String? linkWord;
  final IconData? weatherIcon; final String? weatherText; final Color? alert;
  final VoidCallback onLinks; final VoidCallback onWeather;
  /// Phone: no weather icon (the temperature alone, see [pillWeatherText]).
  final bool compact;
  const LinkWeatherPill({super.key,required this.dot,required this.linkTooltip,required this.onLinks,required this.onWeather,
    this.linkWord,this.weatherIcon,this.weatherText,this.alert,this.compact=false});

  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    final weather=weatherText!=null;
    final r=BorderRadius.circular(pillHeight/2);
    final shape=RoundedRectangleBorder(borderRadius:r);
    return SizedBox(height:pillTouch,child:Stack(alignment:Alignment.center,children:[
      // The drawn pill, 40 px, centred in the 48 px touch area.
      Positioned.fill(top:(pillTouch-pillHeight)/2,bottom:(pillTouch-pillHeight)/2,child:DecoratedBox(
        decoration:BoxDecoration(color:alert??s.surface.withValues(alpha:0.92),borderRadius:r,border:Border.all(color:s.outline)))),
      Material(color:Colors.transparent,child:Row(mainAxisSize:MainAxisSize.min,children:[
        Tooltip(message:linkTooltip,child:InkWell(key:const ValueKey('link-dot'),customBorder:shape,onTap:onLinks,child:ConstrainedBox(
          constraints:const BoxConstraints(minWidth:pillTouch,minHeight:pillTouch),
          child:Padding(padding:EdgeInsets.only(left:14,right:weather?6:14),child:Row(mainAxisSize:MainAxisSize.min,mainAxisAlignment:MainAxisAlignment.center,children:[
            Container(width:10,height:10,decoration:BoxDecoration(color:dot,shape:BoxShape.circle)),
            if(linkWord!=null)...[const SizedBox(width:6),Text(linkWord!,style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:s.onSurface))],
          ]))))),
        if(weather)InkWell(customBorder:shape,onTap:onWeather,child:SizedBox(height:pillTouch,child:Padding(padding:const EdgeInsets.only(left:6,right:14),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            if(weatherIcon!=null&&!compact)...[Icon(weatherIcon,size:16),const SizedBox(width:4)],
            Text(weatherText!,style:const TextStyle(fontSize:13)),
          ])))),
      ])),
    ]));
  }
}
