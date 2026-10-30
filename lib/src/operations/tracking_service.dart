import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../models/position.dart';
import '../l10n/strings.dart';
import '../services/location_service.dart';
import '../services/power_state.dart';

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
  Position? _last;
  /// A new GPS fix arrived since the last position sent.
  bool _fresh=false;

  /// On screen / power saving (battery card, 30 Oct 2026).
  final PowerState power;
  TrackingService({required this.eventId,required this.deviceId,required this.location,required this.onPosition,this._intervalS=30,PowerState? power})
    :power=power??PowerState.instance;

  bool get enabled=>_enabled;
  /// Interval chosen by the operator (bounded by the PCO).
  int get intervalS=>_intervalS;
  Position? get lastFix=>_last;
  /// Last position sent and whether the device moves since (point B).
  Position? _sent; bool _moving=true;
  /// Interval actually used: chosen when moving, 60 s standing still, 2 min
  /// in power-saving mode.
  int get effectiveIntervalS=>adaptiveIntervalS(_intervalS,moving:_moving,saver:power.saver);
  /// iPhone: reduced accuracy in the background or in power-saving mode.
  bool get _reduced=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS&&(!power.foreground||power.saver);
  bool _gpsReduced=false;

  /// False when the location is refused or unavailable.
  Future<bool> start() async {
    if(_enabled)return true;
    if(!await location.ensurePermission())return false;
    _listenGps();
    _enabled=true;
    power.addListener(_onPower);
    _restartTimer();
    notifyListeners();
    return true;
  }

  void _listenGps(){
    _gps?.cancel();
    _gpsReduced=_reduced;
    _gps=location.positions(background:true,reduced:_gpsReduced,title:S.t('tracking.title'),text:S.t('tracking.notification')).listen((p){
      final first=_last==null;
      _last=p; _fresh=true;
      final was=_moving, s=_sent;
      _moving=isMoving(speedMps:p.speed,accuracyM:p.accuracy,
        distanceM:s==null?null:Geolocator.distanceBetween(s.latitude,s.longitude,p.latitude,p.longitude));
      if(first){_send();}
      else if(_moving&&!was){_send();_restartTimer();}
    },onError:(_){});
  }

  /// Screen on / off or power-saving mode changed.
  void _onPower(){
    if(!_enabled)return;
    if(_reduced!=_gpsReduced)_listenGps();
    _restartTimer();
  }

  Future<void> stop() async {
    if(!_enabled)return;
    _enabled=false;
    power.removeListener(_onPower);
    _timer?.cancel(); _timer=null;
    await _gps?.cancel(); _gps=null;
    power.reportTracking();
    notifyListeners();
  }

  void setInterval(int seconds){
    if(seconds==_intervalS)return;
    _intervalS=seconds;
    if(_enabled)_restartTimer();
    notifyListeners();
  }

  /// One-shot timer, set again after each tick with the interval of the
  /// moment (moving or not, power saving).
  void _restartTimer(){
    _timer?.cancel();
    final s=effectiveIntervalS;
    power.reportTracking(intervalS:s,moving:_moving,reduced:_gpsReduced);
    _timer=Timer(Duration(seconds:s),(){_send();if(_enabled)_restartTimer();});
  }

  /// Sends the last fix if it is newer than the last one sent: a device
  /// standing still without a new fix does not repeat the same position.
  Future<void> _send() async {
    final g=_last;
    if(g==null||!_fresh)return;
    _fresh=false; _sent=g;
    await onPosition(SarcadePosition(id:_uuid.v4(),eventId:eventId,deviceId:deviceId,lat:g.latitude,lon:g.longitude,
      time:fixTime(g.timestamp,DateTime.now().toUtc()),altM:g.altitude,accuracyM:g.accuracy,headingDeg:g.heading>=0?g.heading:null,speedMps:g.speed>=0?g.speed:null));
  }

  @override void dispose(){power.removeListener(_onPower);_timer?.cancel();_gps?.cancel();super.dispose();}
}

/// Time of a GPS fix, or now when the fix carries a time that cannot be
/// right: Windows gave positions dated January 1970 (recettes of 13 and
/// 23 October 2026, « Dernière position : 497258 h »).
DateTime fixTime(DateTime gps,DateTime now){
  final t=gps.toUtc();
  if(t.isBefore(DateTime.utc(2020))||t.difference(now).abs()>const Duration(hours:12))return now;
  return t;
}

/// « 30 s », « 2 min ».
String intervalLabel(int s,String Function(String key,Map<String,Object?> args) t)=>
  s<60?t('tracking.everySeconds',{'n':s}):t('tracking.everyMinutes',{'n':s~/60});
