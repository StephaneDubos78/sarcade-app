/// Opening of the fiche « Infos du point » from the map (kept out of
/// operational_map_page.dart, shared by several work sites).
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../services/location_service.dart';
import '../places/readable_place.dart';
import 'point_info_page.dart';

/// A point of the map; [from]: my position for distance and azimuth.
Future<void> openPointInfo(BuildContext context,{required LatLng point,required PlaceDescriber places,LatLng? from,
    void Function(String text)? onSendMessage})=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PointInfoPage(
  point:point,title:S.t('info.title'),places:places,from:from,onSendMessage:onSendMessage)));

/// « Ma position »: a fresh GPS fix (accuracy, time, course, speed, GPS
/// altitude as fallback); [fallback] when the GPS gives nothing.
Future<void> openMyPositionInfo(BuildContext context,{required LocationService location,required PlaceDescriber places,
    LatLng? fallback,void Function(String text)? onSendMessage}) async {
  final fix=await location.current();
  if(!context.mounted)return;
  final point=fix==null?fallback:LatLng(fix.latitude,fix.longitude);
  if(point==null){ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content:Text(S.t('map.noPosition'))));return;}
  double? ok(double v)=>v.isFinite&&v>=0?v:null;
  final gps=fix==null?const GpsFix():GpsFix(accuracyM:ok(fix.accuracy),altitudeM:fix.altitude.isFinite&&fix.altitude!=0?fix.altitude:null,
    headingDeg:ok(fix.heading),speedMps:ok(fix.speed),time:fix.timestamp);
  await Navigator.push(context,MaterialPageRoute(builder:(_)=>PointInfoPage(point:point,title:S.t('info.myPosition'),places:places,
    gps:gps,onSendMessage:onSendMessage)));
}
