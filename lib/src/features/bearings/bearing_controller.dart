import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:uuid/uuid.dart';

import '../../services/location_service.dart';
import '../measure/measure_controller.dart' show compassHeading;
import '../measure/wmm.dart';
import 'bearing_models.dart';

/// Bearings of the event, and the « taking a bearing » mode: live GPS
/// position, compass heading corrected to true north with the WMM
/// declination already used by the measure.
class BearingController extends ChangeNotifier {
  final String eventId, actorId; final LocationService location;
  final Future<void> Function(Bearing b,{required bool isNew}) onSave;
  final Future<void> Function(Bearing b) onDelete;
  BearingController({required this.eventId,required this.actorId,required this.location,required this.onSave,required this.onDelete});

  final Map<String,Bearing> _all={};
  Iterable<Bearing> get all=>_all.values;
  Bearing? byId(String id)=>_all[id];

  void applyRemote(Bearing b){final k=_all[b.id];if(k==null||!k.updatedAt.isAfter(b.updatedAt)){_all[b.id]=b;notifyListeners();}}
  void remove(String id){if(_all.remove(id)!=null)notifyListeners();}

  // --- taking a bearing ---
  bool taking=false;
  LatLng? position; double? accuracyM, magneticDeg, manualDeg;
  StreamSubscription? _gps,_acc,_mag; List<double>? _gravity,_field;
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
    try{
      _acc=accelerometerEventStream().listen((e){_gravity=[e.x,e.y,e.z];_heading();},onError:(_){});
      _mag=magnetometerEventStream().listen((e){_field=[e.x,e.y,e.z];_heading();},onError:(_){});
    }catch(_){/* no sensor: typed azimuth */}
  }
  void _heading(){
    final g=_gravity,f=_field; if(g==null||f==null)return;
    final h=compassHeading(g,f); if(h!=null&&manualDeg==null){magneticDeg=h;notifyListeners();}
  }
  void setManual(double? deg){manualDeg=deg==null?null:(deg%360+360)%360;notifyListeners();}
  void setPosition(LatLng p){position=p;accuracyM=null;notifyListeners();}

  void stopTaking(){_stopSensors();notifyListeners();}
  void _stopSensors(){taking=false; _gps?.cancel(); _acc?.cancel(); _mag?.cancel(); _gps=_acc=_mag=null; _gravity=_field=null;}

  /// The bearing being taken, as it would be saved.
  Bearing? draft({String target='',int strength=0,String comment='',String search=''}){
    final p=position, az=trueDeg; if(p==null||az==null)return null;
    final now=DateTime.now().toUtc();
    return Bearing(id:'draft',eventId:eventId,origin:p,azimuthDeg:az,strength:strength,target:target,comment:comment,search:search,
      method:manualDeg!=null?'manual':'compass',magneticDeg:manualDeg==null?magneticDeg:null,declinationDeg:manualDeg==null?declinationDeg:null,
      accuracyM:accuracyM,takenAt:now,createdBy:actorId,updatedBy:actorId,updatedAt:now);
  }

  Future<Bearing?> save({String target='',int strength=0,String comment='',String search=''}) async {
    final d=draft(target:target,strength:strength,comment:comment,search:search); if(d==null)return null;
    final b=Bearing.fromJson({...d.toJson(),'id':const Uuid().v4()});
    _all[b.id]=b; stopTaking();
    await onSave(b,isNew:true);
    return b;
  }

  Future<void> update(Bearing b) async {_all[b.id]=b;notifyListeners();await onSave(b,isNew:false);}
  Future<void> delete(Bearing b) async {_all.remove(b.id);notifyListeners();await onDelete(b);}

  // No notification while disposing: the page is already gone.
  @override void dispose(){_stopSensors();super.dispose();}
}
