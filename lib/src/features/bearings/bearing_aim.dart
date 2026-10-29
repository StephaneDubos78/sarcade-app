import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' as geo;
import 'bearing_models.dart';

/// Bearing taken with the mouse on a computer (decision of the project
/// owner, 29 Oct 2026, 19 h): an arrow leaves the chosen point and its tip
/// follows the mouse, the azimuth updating live; a click fixes the tip, a
/// click on the tip moves it again; Shift snaps to 5°. Only « Enregistrer »
/// brings the line back to the usual length of the bearings.
class BearingAim {
  final LatLng origin;
  LatLng? tip;
  double? azimuthDeg;
  /// Tip fixed by a click: the mouse no longer moves it.
  bool fixed=false;
  /// Time of the bearing, corrected in the panel.
  DateTime takenAt=DateTime.now().toUtc();
  BearingAim(this.origin);

  /// Free length during the aim, in metres (0 before the first move).
  double get lengthM=>tip==null?0:geo.distanceM(origin,tip!);

  /// Mouse moved: the tip follows unless fixed.
  bool follow(LatLng p,{bool snap=false}){if(fixed)return false;_set(p,snap);return true;}
  /// Click: the tip stays there.
  void fix(LatLng p,{bool snap=false}){_set(p,snap);fixed=true;}
  /// Click on the tip: it follows the mouse again.
  void release(){fixed=false;}
  /// Azimuth corrected with the keyboard: same length, tip fixed.
  void type(double deg){
    final az=normDeg(deg), d=lengthM>1?lengthM:aimDefaultM;
    azimuthDeg=az; tip=geo.destination(origin,d,az); fixed=true;
  }
  void _set(LatLng p,bool snap){
    final az=aimAzimuth(origin,p,snap:snap);
    azimuthDeg=az; tip=snap?geo.destination(origin,geo.distanceM(origin,p),az):p;
  }
}

/// Length given to the tip when the azimuth is typed before any move.
const aimDefaultM=2000.0;

/// Degrees in [0, 360).
double normDeg(double d)=>(d%360+360)%360;
/// Nearest multiple of [step] degrees, in [0, 360).
double snapDeg(double d,{double step=5})=>normDeg((normDeg(d)/step).round()*step);
/// True azimuth from the origin to the mouse, snapped to 5° with Shift.
double aimAzimuth(LatLng origin,LatLng mouse,{bool snap=false}){final a=geo.bearingDeg(origin,mouse);return snap?snapDeg(a):a;}
/// Length of the saved line: the one of the preferences, else the usual
/// length of the bearings (10 km), whatever the length drawn.
double savedLengthM([double? preference])=>preference==null||preference.isNaN||preference<=0?defaultBearingLengthM:preference;
const defaultBearingLengthM=10000.0;
/// Click close enough to the tip (screen pixels) to take it again.
bool nearTip(Offset click,Offset tip,{double px=18})=>(click-tip).distance<=px;
/// Typed azimuth « 123 », « 123,5 »: null when not between 0 and 360.
double? parseAzimuth(String text){final d=double.tryParse(text.replaceAll(',','.').replaceAll('°','').trim());return d==null||d<0||d>360?null:normDeg(d);}

/// Arrow head and handle at the tip (map north up, rotation off).
List<Widget> buildAimLayers(BearingAim aim,Color colour){
  final tip=aim.tip, az=aim.azimuthDeg; if(tip==null||az==null)return const [];
  return [MarkerLayer(markers:[Marker(point:tip,width:36,height:36,child:MouseRegion(cursor:aim.fixed?SystemMouseCursors.grab:SystemMouseCursors.precise,
    child:Transform.rotate(angle:az*math.pi/180,child:Icon(Icons.navigation,size:30,color:colour,shadows:const [Shadow(blurRadius:3,color:Colors.black54)]))))])];
}

/// Azimuth and time of the mouse bearing, corrected with the keyboard.
class AimFields extends StatefulWidget {
  final double? azimuthDeg; final DateTime takenAt;
  final void Function(double) onAzimuth; final void Function(DateTime) onTime;
  const AimFields({super.key,required this.azimuthDeg,required this.takenAt,required this.onAzimuth,required this.onTime});
  @override State<AimFields> createState()=>_AimFieldsState();
}

class _AimFieldsState extends State<AimFields> {
  final _az=TextEditingController(), _time=TextEditingController();
  final _azFocus=FocusNode(), _timeFocus=FocusNode();
  @override void initState(){super.initState();_sync();}
  @override void didUpdateWidget(AimFields old){super.didUpdateWidget(old);_sync();}
  // Live azimuth in the field, unless being typed.
  void _sync(){
    if(!_azFocus.hasFocus)_az.text=widget.azimuthDeg==null?'':widget.azimuthDeg!.toStringAsFixed(0).padLeft(3,'0');
    if(!_timeFocus.hasFocus)_time.text=hhmm(widget.takenAt);
  }
  void _submitAz(String v){final d=parseAzimuth(v);if(d!=null)widget.onAzimuth(d);_azFocus.unfocus();}
  void _submitTime(String v){widget.onTime(withHhmm(widget.takenAt,v));_timeFocus.unfocus();}
  @override void dispose(){_az.dispose();_time.dispose();_azFocus.dispose();_timeFocus.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Row(children:[
    Expanded(child:TextField(key:const ValueKey('aim-azimuth'),controller:_az,focusNode:_azFocus,keyboardType:const TextInputType.numberWithOptions(decimal:true),
      decoration:InputDecoration(isDense:true,labelText:S.t('bearings.azimuth'),suffixText:'°'),onSubmitted:_submitAz,onTapOutside:(_){if(_azFocus.hasFocus)_submitAz(_az.text);})),
    const SizedBox(width:10),
    SizedBox(width:110,child:TextField(controller:_time,focusNode:_timeFocus,keyboardType:TextInputType.datetime,
      decoration:InputDecoration(isDense:true,labelText:S.t('bearings.time'),hintText:'14:05'),onSubmitted:_submitTime,onTapOutside:(_){if(_timeFocus.hasFocus)_submitTime(_time.text);})),
  ]);
}
