import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// False when location is off, refused, or not available on this device,
  /// for example a Chromebook or a Linux PC without a location provider.
  Future<bool> ensurePermission() async {
    try{
      if(!await Geolocator.isLocationServiceEnabled())return false;
      var p=await Geolocator.checkPermission();
      if(p==LocationPermission.denied)p=await Geolocator.requestPermission();
      return p==LocationPermission.always||p==LocationPermission.whileInUse;
    }catch(_){
      return false;
    }
  }

  /// Current position, null when unavailable.
  Future<Position?> current() async {
    try{return await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:20)));}
    catch(_){try{return await Geolocator.getLastKnownPosition();}catch(_){return null;}}
  }

  /// Positions while the app runs. With [background] (Beacon), Android keeps
  /// sending from a foreground service with a permanent notification, so
  /// that positions keep reaching the PCO screen off or app in background.
  Stream<Position> positions({bool background=false,String? title,String? text}){
    if(background&&!kIsWeb&&defaultTargetPlatform==TargetPlatform.android){
      return Geolocator.getPositionStream(locationSettings:AndroidSettings(accuracy:LocationAccuracy.high,distanceFilter:5,
        foregroundNotificationConfig:ForegroundNotificationConfig(notificationTitle:title??'SARCADE',
          notificationText:text??'Suivi de position actif',enableWakeLock:true,setOngoing:true)));
    }
    return Geolocator.getPositionStream(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:5));
  }
}
