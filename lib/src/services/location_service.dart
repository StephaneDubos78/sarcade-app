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

  Stream<Position> positions()=>Geolocator.getPositionStream(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:5));
}
