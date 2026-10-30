/// Bearing with the mouse, compact top banner (card « Relevé à la souris,
/// bandeau du haut plus compact », 30 Oct 2026, 12 h 44): one line only,
/// azimuth about two thirds of the former size, GPS coordinates and time on
/// the right, help (clic, Maj, Échap) in the tooltip of a small ⓘ, close
/// cross. [glideMapTo]: the map centres on the origin of the bearing with a
/// short animation, zoom kept.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';

class MouseBearingHud extends StatelessWidget {
  final double? trueDeg, magneticDeg, accuracyM;
  final LatLng? position;
  final DateTime time;
  final VoidCallback onClose;
  final BoxDecoration decoration;
  const MouseBearingHud({super.key,required this.trueDeg,required this.magneticDeg,required this.position,required this.accuracyM,
    required this.time,required this.onClose,required this.decoration});

  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    String two(int v)=>v.toString().padLeft(2,'0');
    final az=trueDeg, mag=magneticDeg, p=position;
    final where=[p==null?S.t('bearings.noPosition'):'${p.latitude.toStringAsFixed(4)}° N · ${p.longitude.toStringAsFixed(4)}° E',
      if(accuracyM!=null)'±${accuracyM!.toStringAsFixed(0)} m','${two(time.hour)}:${two(time.minute)}:${two(time.second)}'].join(' · ');
    return Container(key:const ValueKey('bearing-mouse-hud'),padding:const EdgeInsets.fromLTRB(14,4,4,4),decoration:decoration,
      child:Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        Text(az==null?'—':'${az.toStringAsFixed(0).padLeft(3,'0')}°',
          style:const TextStyle(fontSize:40,fontWeight:FontWeight.w500,height:1,fontFeatures:[FontFeature.tabularFigures()])),
        const SizedBox(width:8),
        Text([S.t('bearings.true'),if(mag!=null)'(${S.t('bearings.magnetic',{'v':mag.toStringAsFixed(0).padLeft(3,'0')})})'].join('\n'),
          style:TextStyle(fontSize:11,color:s.onSurfaceVariant)),
        const SizedBox(width:12),
        Expanded(child:Text(where,textAlign:TextAlign.end,maxLines:2,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontSize:12,fontFamily:'monospace',color:s.onSurfaceVariant))),
        Tooltip(message:S.t('bearings.aimMouseHelp'),child:Padding(padding:const EdgeInsets.symmetric(horizontal:6),
          child:Icon(Icons.info_outline,size:18,color:s.onSurfaceVariant))),
        IconButton(tooltip:S.t('common.cancel'),onPressed:onClose,icon:const Icon(Icons.close)),
      ]));
  }
}

/// Moves the map to [target] in about [duration], zoom and rotation kept.
void glideMapTo(MapController map,LatLng target,{Duration duration=const Duration(milliseconds:350)}){
  LatLng from; double zoom;
  try{from=map.camera.center;zoom=map.camera.zoom;}catch(_){return;}
  const step=Duration(milliseconds:16);
  final steps=(duration.inMilliseconds/step.inMilliseconds).ceil().clamp(1,100);
  var i=0;
  Timer.periodic(step,(t){
    i++;
    final x=(i/steps).clamp(0.0,1.0);
    final e=Curves.easeInOut.transform(x);
    try{
      map.move(LatLng(from.latitude+(target.latitude-from.latitude)*e,from.longitude+(target.longitude-from.longitude)*e),zoom);
    }catch(_){t.cancel();return;}
    if(i>=steps)t.cancel();
  });
}
