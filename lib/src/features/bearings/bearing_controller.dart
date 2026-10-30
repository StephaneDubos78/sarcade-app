import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../services/location_service.dart';
import '../compass/shared_compass.dart';
import '../measure/wmm.dart';
import 'bearing_models.dart';

/// Bearings of the event, and the « taking a bearing » mode: live GPS
/// position, compass heading corrected to true north with the WMM
/// declination already used by the measure.
class BearingController extends ChangeNotifier {
  final String eventId, actorId; final LocationService location;
  final Future<void> Function(Bearing b,{required bool isNew}) onSave;
  final Future<void> Function(Bearing b) onDelete;
  /// One compass for the whole app (shared_compass.dart).
  final SharedCompass compass;
  BearingController({required this.eventId,required this.actorId,required this.location,required this.onSave,required this.onDelete,SharedCompass? compass})
    :compass=compass??SharedCompass.instance;

  final Map<String,Bearing> _all={};
  Iterable<Bearing> get all=>_all.values;
  Bearing? byId(String id)=>_all[id];

  void applyRemote(Bearing b){final k=_all[b.id];if(k==null||!k.updatedAt.isAfter(b.updatedAt)){_all[b.id]=b;notifyListeners();}}
  void remove(String id){if(_all.remove(id)!=null)notifyListeners();}

  // --- taking a bearing ---
  bool taking=false;
  LatLng? position; double? accuracyM, magneticDeg, manualDeg;
  StreamSubscription? _gps; bool _compassOn=false;
  /// Averaging the compass over 2 s before saving (« ± x° »).
  bool averaging=false;
  /// Spread of the last saved bearing averaged over 2 s, degrees.
  double? lastSpreadDeg;
  /// The system asks for a calibration (figure of 8).
  bool get needsCalibration=>_compassOn&&compass.calibrate;
  double? get compassAccuracyDeg=>compass.accuracyDeg;
  /// Compass seen at least once: else the azimuth is typed (PC, Chromebook).
  bool get hasCompass=>magneticDeg!=null;
  double? get declinationDeg=>position==null?null:magneticDeclination(position!.latitude,position!.longitude,DateTime.now().toUtc());
  /// True azimuth: typed, else compass + declination.
  double? get trueDeg{
    if(manualDeg!=null)return manualDeg;
    final m=magneticDeg,d=declinationDeg;
    return m==null||d==null?null:(m+d+360)%360;
  }

  Future<void> startTaking({LatLng? from}) async {
    taking=true; manualDeg=null; magneticDeg=null; position=from; accuracyM=null; notifyListeners();
    if(from==null&&await location.ensurePermission()){
      final p=await location.current();
      if(p!=null&&taking){position=LatLng(p.latitude,p.longitude);accuracyM=p.accuracy;notifyListeners();}
      _gps=location.positions().listen((p){position=LatLng(p.latitude,p.longitude);accuracyM=p.accuracy;notifyListeners();},onError:(_){});
    }
    // Browser: no compass for the bearing, as before (azimuth typed or mouse).
    if(taking&&!kIsWeb&&!_compassOn){_compassOn=true;compass.start();compass.addListener(_heading);}
  }
  void _heading(){
    final h=compass.heading; if(manualDeg==null&&h!=magneticDeg){magneticDeg=h;notifyListeners();}
    else if(compass.calibrate){notifyListeners();}
  }
  void setManual(double? deg){manualDeg=deg==null?null:(deg%360+360)%360;notifyListeners();}
  void setPosition(LatLng p){position=p;accuracyM=null;notifyListeners();}

  void stopTaking(){_stopSensors();notifyListeners();}
  void _stopSensors(){taking=false; _gps?.cancel(); _gps=null;
    if(_compassOn){_compassOn=false;compass.removeListener(_heading);compass.stop();}}

  /// The bearing being taken, as it would be saved.
  /// Colour of this operator, kept with each bearing.
  int? operatorColor;

  Bearing? draft({String target='',int strength=0,String comment='',String search='',double? lengthM,DateTime? takenAt,String? method}){
    final p=position, az=trueDeg; if(p==null||az==null)return null;
    final now=DateTime.now().toUtc();
    return Bearing(id:'draft',eventId:eventId,origin:p,azimuthDeg:az,lengthM:lengthM??10000,strength:strength,target:target,comment:comment,search:search,
      method:method??(manualDeg!=null?'manual':'compass'),magneticDeg:manualDeg==null?magneticDeg:null,declinationDeg:manualDeg==null?declinationDeg:null,
      accuracyM:accuracyM,operatorColor:operatorColor,takenAt:takenAt??now,createdBy:actorId,updatedBy:actorId,updatedAt:now);
  }

  /// [lengthM], [takenAt], [method]: bearing taken with the mouse (bearing_aim.dart).
  Future<Bearing?> save({String target='',int strength=0,String comment='',String search='',bool exercise=false,double? frequencyMhz,double? lengthM,DateTime? takenAt,String? method}) async {
    lastSpreadDeg=null;
    // Compass: mean of the readings over 2 s, with their spread.
    if(manualDeg==null&&method==null&&magneticDeg!=null&&!averaging){
      averaging=true; notifyListeners();
      final avg=await compass.average();
      averaging=false;
      if(!taking)return null;
      if(avg!=null){magneticDeg=avg.mean;lastSpreadDeg=avg.spread;}
    }
    final d=draft(target:target,strength:strength,comment:comment,search:search,lengthM:lengthM,takenAt:takenAt,method:method); if(d==null)return null;
    final b=Bearing.fromJson({...d.copyWith(exercise:exercise,frequencyMhz:frequencyMhz,updatedBy:d.updatedBy,updatedAt:d.updatedAt).toJson(),'id':const Uuid().v4()});
    _all[b.id]=b; stopTaking();
    await onSave(b,isNew:true);
    return b;
  }

  Future<void> update(Bearing b) async {_all[b.id]=b;notifyListeners();await onSave(b,isNew:false);}
  Future<void> delete(Bearing b) async {_all.remove(b.id);notifyListeners();await onDelete(b);}

  // No notification while disposing: the page is already gone.
  @override void dispose(){_stopSensors();super.dispose();}
}
