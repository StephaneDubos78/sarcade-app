import 'package:geolocator/geolocator.dart';
class LocationService {
 Future<bool> ensurePermission() async {if(!await Geolocator.isLocationServiceEnabled()) return false;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();return p==LocationPermission.always||p==LocationPermission.whileInUse;}
 Stream<Position> positions()=>Geolocator.getPositionStream(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:5));
}
