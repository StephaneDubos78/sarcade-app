import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../services/location_service.dart';
import '../map/drawing/geometry.dart' as geo;
import 'wmm.dart';

/// Origin of the measure: my position (updated continuously), or a fixed
/// point (PCO, a team, a point of the map) on devices without GPS.
class MeasureOrigin {
  final LatLng point; final String label; final bool mine; final double? accuracyM; final DateTime? time;
  const MeasureOrigin({required this.point,required this.label,this.mine=false,this.accuracyM,this.time});
}

/// Distance and azimuth from the operator to a designated point (note
/// « Mesure de distance vers un point désigné »): personal, computed on the
/// device without network, true and magnetic azimuth (WMM), guidance arrow
/// oriented by the compass on phones.
class MeasureController extends ChangeNotifier {
  final LocationService location;
  MeasureController({required this.location});

  MeasureOrigin? origin; LatLng? target; String targetLabel='';
  /// Manual declination set by the operator (special cases), else WMM.
  double? declinationOverride;
  /// Magnetic heading of the device (compass), degrees, null without sensor.
  double? heading;
  StreamSubscription<Position>? _gps;
  StreamSubscription<AccelerometerEvent>? _acc; StreamSubscription<MagnetometerEvent>? _mag;
  List<double>? _gravity, _field;

  bool get active=>target!=null;

  Future<void> start(LatLng to,String label,{MeasureOrigin? from}) async {
    await _stopGps();
    target=to; targetLabel=label;
    if(from!=null){origin=from;notifyListeners();return;}
    final here=await location.current();
    if(here!=null){
      origin=MeasureOrigin(point:LatLng(here.latitude,here.longitude),label:'',mine:true,accuracyM:here.accuracy,time:here.timestamp);
      _gps=location.positions().listen((p){
        origin=MeasureOrigin(point:LatLng(p.latitude,p.longitude),label:'',mine:true,accuracyM:p.accuracy,time:p.timestamp);
        notifyListeners();
      },onError:(_){});
    }else{
      origin=null;
    }
    notifyListeners();
  }

  void setOrigin(MeasureOrigin o){_stopGps();origin=o;notifyListeners();}

  double? get distanceM=>origin==null||target==null?null:geo.distanceM(origin!.point,target!);
  double? get trueAzimuth=>origin==null||target==null?null:geo.bearingDeg(origin!.point,target!);
  /// Declination of the World Magnetic Model at the origin, always computed
  /// so that it is shown next to a manual value.
  double get wmmDeclination=>origin==null?0:magneticDeclination(origin!.point.latitude,origin!.point.longitude,DateTime.now());
  double get declination=>declinationOverride??wmmDeclination;
  bool get manualDeclination=>declinationOverride!=null;
  /// WMM2025 is valid until 2030.0: afterwards a warning asks for an update
  /// of the application (decision of 10 Oct 2026).
  static bool wmmExpired([DateTime? now])=>decimalYear(now??DateTime.now())>=wmmValidUntil;
  double? get magneticAzimuth{final t=trueAzimuth;return t==null?null:(t-declination+360)%360;}
  /// Age of my position, for « position ancienne de X min ».
  Duration? get originAge=>origin?.time==null?null:DateTime.now().toUtc().difference(origin!.time!.toUtc());
  bool get originStale=>origin?.mine==true&&(originAge?.inMinutes??0)>=2;

  /// Angle of the guidance arrow relative to the top of the phone.
  double? get arrowAngle{
    final m=magneticAzimuth, h=heading;
    return m==null||h==null?null:(m-h+360)%360;
  }

  /// Compass from the accelerometer and the magnetometer (Android, iOS).
  void startCompass(){
    if(_acc!=null)return;
    try{
      _acc=accelerometerEventStream().listen((e){_gravity=[e.x,e.y,e.z];_updateHeading();},onError:(_){});
      _mag=magnetometerEventStream().listen((e){_field=[e.x,e.y,e.z];_updateHeading();},onError:(_){});
    }catch(_){/* no sensor on this device */}
  }

  void _updateHeading(){
    final g=_gravity, f=_field;
    if(g==null||f==null)return;
    final h=compassHeading(g,f);
    if(h!=null){heading=h;notifyListeners();}
  }

  void stopCompass(){_acc?.cancel();_mag?.cancel();_acc=null;_mag=null;heading=null;}

  Future<void> clear() async {
    await _stopGps(); stopCompass();
    target=null; origin=null;
    notifyListeners();
  }

  Future<void> _stopGps() async {await _gps?.cancel();_gps=null;}

  @override void dispose(){_gps?.cancel();stopCompass();super.dispose();}
}

/// Magnetic heading of the top of the device (degrees from magnetic north),
/// tilt compensated, from gravity and magnetic field in device axes (same
/// computation as Android SensorManager.getRotationMatrix). Null when the
/// device is in free fall or close to a strong magnetic disturbance.
double? compassHeading(List<double> gravity,List<double> field){
  final ax=gravity[0], ay=gravity[1], az=gravity[2];
  final ex=field[0], ey=field[1], ez=field[2];
  var hx=ey*az-ez*ay, hy=ez*ax-ex*az, hz=ex*ay-ey*ax;
  final normH=math.sqrt(hx*hx+hy*hy+hz*hz);
  if(normH<0.1)return null;
  hx/=normH; hy/=normH; hz/=normH;
  final normA=math.sqrt(ax*ax+ay*ay+az*az);
  if(normA<0.1)return null;
  final nax=ax/normA, naz=az/normA;
  final my=naz*hx-nax*hz;
  return (math.atan2(hy,my)*180/math.pi+360)%360;
}

/// Declination typed by the operator: « 2,5 », « -1.2 », « 2.5 E », « 1,2 O »,
/// « 1.2W ». Positive east. Null when not understood or beyond 90°.
double? parseDeclination(String text){
  final m=RegExp(r'^\s*([+-]?\d{1,2}(?:[.,]\d+)?)\s*°?\s*([EOW])?\s*$').firstMatch(text.trim().toUpperCase());
  if(m==null)return null;
  var v=double.parse(m[1]!.replaceAll(',','.'));
  if(m[2]=='O'||m[2]=='W')v=-v.abs();
  if(m[2]=='E')v=v.abs();
  return v.abs()<=90?v:null;
}

/// « 2,0° E », « 1,5° O » (French), « 1.5° W » (English).
String formatDeclination(double d,{String decimal=',',String east='E',String west='O'})=>
  '${d.abs().toStringAsFixed(1).replaceAll('.',decimal)}° ${d>=0?east:west}';
