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
  /// Help in the ⓘ tooltip (mouse by default; « Visez la source avec le
  /// haut du téléphone » with the compass, card of 30 Oct 2026, 16 h 25).
  final String? help;
  /// « vrai » (default) or « saisi » after the azimuth.
  final String? trueLabel;
  /// Under the line: compass accuracy, calibration.
  final Widget? below;
  const MouseBearingHud({super.key,required this.trueDeg,required this.magneticDeg,required this.position,required this.accuracyM,
    required this.time,required this.onClose,required this.decoration,this.help,this.trueLabel,this.below});

  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    String two(int v)=>v.toString().padLeft(2,'0');
    final az=trueDeg, mag=magneticDeg, p=position;
    final where=[p==null?S.t('bearings.noPosition'):'${p.latitude.toStringAsFixed(4)}° N · ${p.longitude.toStringAsFixed(4)}° E',
      if(accuracyM!=null)'±${accuracyM!.toStringAsFixed(0)} m','${two(time.hour)}:${two(time.minute)}:${two(time.second)}'].join(' · ');
    final line=Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
        Text(az==null?'—':'${az.toStringAsFixed(0).padLeft(3,'0')}°',
          style:const TextStyle(fontSize:40,fontWeight:FontWeight.w500,height:1,fontFeatures:[FontFeature.tabularFigures()])),
        const SizedBox(width:8),
        Text([trueLabel??S.t('bearings.true'),if(mag!=null)'(${S.t('bearings.magnetic',{'v':mag.toStringAsFixed(0).padLeft(3,'0')})})'].join('\n'),
          style:TextStyle(fontSize:11,color:s.onSurfaceVariant)),
        const SizedBox(width:12),
        Expanded(child:Text(where,textAlign:TextAlign.end,maxLines:2,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontSize:12,fontFamily:'monospace',color:s.onSurfaceVariant))),
        Tooltip(message:help??S.t('bearings.aimMouseHelp'),child:Padding(padding:const EdgeInsets.symmetric(horizontal:6),
          child:Icon(Icons.info_outline,size:18,color:s.onSurfaceVariant))),
        IconButton(tooltip:S.t('common.cancel'),onPressed:onClose,icon:const Icon(Icons.close)),
      ]);
    return Container(key:const ValueKey('bearing-mouse-hud'),padding:const EdgeInsets.fromLTRB(14,4,4,4),decoration:decoration,
      child:below==null?line:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[line,Padding(padding:const EdgeInsets.only(bottom:6),child:below!)]));
  }
}

/// Where the origin of a bearing goes on the screen, as a fraction of the
/// map (card « Relevé au doigt : la carte ne se centre pas », 31 Oct 2026):
/// the middle of the part left visible between the top banner and the
/// bearing sheet — on a phone the sheet covers the bottom, on a computer
/// or a tablet the sheet of the mouse bearing takes [rightSheetPx] on the
/// right.
Offset bearingFocus(Size map,{required bool phone,double rightSheetPx=0}){
  if(phone)return Offset(map.width/2,map.height*0.32);
  return Offset((map.width-rightSheetPx)/2,map.height*0.45);
}

/// Map centre that puts [target] at [focus] on the screen (zoom and
/// rotation kept); [project] and [unproject] are the camera conversions.
LatLng centreFor(LatLng target,Offset focus,Size map,Offset Function(LatLng) project,LatLng Function(Offset) unproject){
  final p=project(target);
  return unproject(p+Offset(map.width/2,map.height/2)-focus);
}

/// Moves the map to [target] in about [duration], zoom and rotation kept;
/// with [focus], [target] ends there on the screen instead of the centre.
void glideMapTo(MapController map,LatLng target,{Duration duration=const Duration(milliseconds:350),Offset? focus}){
  LatLng from; double zoom;
  try{
    from=map.camera.center;zoom=map.camera.zoom;
    if(focus!=null){
      final c=map.camera; final size=Size(c.nonRotatedSize.width,c.nonRotatedSize.height);
      target=centreFor(target,focus,size,c.latLngToScreenOffset,c.screenOffsetToLatLng);
    }
  }catch(_){return;}
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

/// Azimuth typed without a compass (« 45 », « 045 », « 45,5 »); null when
/// it is not a number from 0 to 360 (revue d'ergonomie n° 12).
double? parseAzimuth(String text){
  final v=double.tryParse(text.trim().replaceAll(',','.').replaceAll('°',''));
  if(v==null||v<0||v>360)return null;
  return v==360?0:v;
}

/// No compass (computer, some tablets): « Relevé » and a visible
/// « Azimut (°) » field, « ex. 045 » (revue d'ergonomie n° 12).
class TypedBearingHud extends StatefulWidget {
  final LatLng? position; final double? accuracyM; final DateTime time;
  final ValueChanged<double> onAzimuth; final VoidCallback onClose; final BoxDecoration decoration;
  const TypedBearingHud({super.key,required this.position,required this.accuracyM,required this.time,required this.onAzimuth,
    required this.onClose,required this.decoration});
  @override State<TypedBearingHud> createState()=>_TypedBearingHudState();
}

class _TypedBearingHudState extends State<TypedBearingHud> {
  final _ctrl=TextEditingController(); String? _error;
  @override void dispose(){_ctrl.dispose();super.dispose();}
  void _apply(){
    final v=parseAzimuth(_ctrl.text);
    setState(()=>_error=v==null&&_ctrl.text.trim().isNotEmpty?S.t('bearings.typeHelp'):null);
    if(v!=null)widget.onAzimuth(v);
  }
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    final p=widget.position;
    return Container(key:const ValueKey('bearing-typed-hud'),padding:const EdgeInsets.fromLTRB(14,8,4,8),decoration:widget.decoration,
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Text(S.t('bearings.title'),style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(width:12),
          Expanded(child:Text(S.t('bearings.noCompassHelp'),style:TextStyle(fontSize:12,color:s.onSurfaceVariant))),
          IconButton(tooltip:S.t('common.cancel'),onPressed:widget.onClose,icon:const Icon(Icons.close)),
        ]),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:150,child:TextField(key:const ValueKey('bearing-typed-azimuth'),controller:_ctrl,autofocus:true,
            keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>_apply(),onSubmitted:(_)=>_apply(),
            decoration:InputDecoration(labelText:S.t('bearings.azimuthField'),hintText:S.t('bearings.azimuthHint'),suffixText:'°',errorText:_error,isDense:true))),
          const SizedBox(width:12),
          Expanded(child:Padding(padding:const EdgeInsets.only(top:10,right:8),child:Text(
            [p==null?S.t('bearings.noPosition'):'${p.latitude.toStringAsFixed(4)}° N · ${p.longitude.toStringAsFixed(4)}° E',
              if(widget.accuracyM!=null)'±${widget.accuracyM!.toStringAsFixed(0)} m'].join(' · '),
            textAlign:TextAlign.end,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,fontFamily:'monospace',color:s.onSurfaceVariant)))),
        ]),
      ]));
  }
}
