/// Follow mode of the navigation (decisions of 10 Oct 2026): the map stays
/// centred on the operator and turns in the direction of travel (GPS course
/// when moving, compass when stationary). Automatic on phones and tablets,
/// north up by default on computers with an option to turn. Touching the
/// map leaves the mode, « Re-centre » comes back to it. Pure code.
library;

import 'package:latlong2/latlong.dart';
import '../map/drawing/geometry.dart';

/// Speed above which the GPS course is reliable (m/s, about 5 km/h).
const followCourseMinSpeed=1.5;
/// Zoom used when the follow mode starts below it.
const followMinZoom=16.0;
/// Distance from the start that engages the follow mode when variants were
/// shown first (the operator chose by moving off).
const followEngageDistanceM=25.0;

/// Heading to put at the top of the map, null for north up.
double? followHeading({double? course,double? speedMs,double? compassTrue,required bool rotate}){
  if(!rotate)return null;
  if(course!=null&&(speedMs??0)>followCourseMinSpeed)return course;
  return compassTrue;
}

/// Rotation of the map (degrees, clockwise) that puts [heading] at the top.
double mapRotationFor(double? heading)=>heading==null?0:(360-heading)%360;

/// Whether a new camera is worth it: the operator moved, or the map would
/// turn by at least [minTurnDeg].
bool followNeedsUpdate({LatLng? lastCenter,double? lastRotation,required LatLng center,required double rotation,
    double minMoveM=2,double minTurnDeg=3}){
  if(lastCenter==null||lastRotation==null)return true;
  final turn=((rotation-lastRotation+540)%360-180).abs();
  return distanceM(lastCenter,center)>=minMoveM||turn>=minTurnDeg;
}
