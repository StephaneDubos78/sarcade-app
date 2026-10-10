import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/position.dart';
import '../services/location_service.dart';

/// Position tracking (« Suivi de position », Beacon in English): when on,
/// the last GPS fix is sent to the PCO at the interval chosen by the
/// operator, within the bounds set by the PCO, who may also require it.
class TrackingService extends ChangeNotifier {
  final String eventId, deviceId;
  final LocationService location;
  /// Called with each position to send (stored and queued by the caller).
  final Future<void> Function(SarcadePosition) onPosition;
  final _uuid=const Uuid();

  bool _enabled=false; int _intervalS;
  StreamSubscription<Position>? _gps; Timer? _timer;
  Position? _last; DateTime? _lastSentFix;

  TrackingService({required this.eventId,required this.deviceId,required this.location,required this.onPosition,this._intervalS=30});

  bool get enabled=>_enabled;
  int get intervalS=>_intervalS;
  Position? get lastFix=>_last;

  /// False when the location is refused or unavailable.
  Future<bool> start() async {
    if(_enabled)return true;
    if(!await location.ensurePermission())return false;
    _gps=location.positions().listen((p){
      final first=_last==null;
      _last=p;
      if(first)_send();
    },onError:(_){});
    _enabled=true;
    _restartTimer();
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    if(!_enabled)return;
    _enabled=false;
    _timer?.cancel(); _timer=null;
    await _gps?.cancel(); _gps=null;
    notifyListeners();
  }

  void setInterval(int seconds){
    if(seconds==_intervalS)return;
    _intervalS=seconds;
    if(_enabled)_restartTimer();
    notifyListeners();
  }

  void _restartTimer(){
    _timer?.cancel();
    _timer=Timer.periodic(Duration(seconds:_intervalS),(_)=>_send());
  }

  /// Sends the last fix if it is newer than the last one sent: a device
  /// standing still without a new fix does not repeat the same position.
  Future<void> _send() async {
    final g=_last;
    if(g==null||(_lastSentFix!=null&&!g.timestamp.isAfter(_lastSentFix!)))return;
    _lastSentFix=g.timestamp;
    await onPosition(SarcadePosition(id:_uuid.v4(),eventId:eventId,deviceId:deviceId,lat:g.latitude,lon:g.longitude,
      time:g.timestamp,altM:g.altitude,accuracyM:g.accuracy,headingDeg:g.heading>=0?g.heading:null,speedMps:g.speed>=0?g.speed:null));
  }

  @override void dispose(){_timer?.cancel();_gps?.cancel();super.dispose();}
}

/// « 30 s », « 2 min ».
String intervalLabel(int s,String Function(String key,Map<String,Object?> args) t)=>
  s<60?t('tracking.everySeconds',{'n':s}):t('tracking.everyMinutes',{'n':s~/60});
