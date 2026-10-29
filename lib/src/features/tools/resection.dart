/// Résection plus complète (menu Outils, validated on 29 Oct 2026): a panel
/// beside the map instead of a small window. Two or three sights towards
/// known points (high points, relays, or any point touched on the map), the
/// azimuth typed or taken with the compass, true or magnetic with the
/// declination shown, a warning when the sights cross at a narrow angle, and
/// the result drawn on the map with its uncertainty circle.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/reference_site.dart';
import '../bearings/bearing_models.dart' show resection;
import '../map/drawing/geometry.dart' as geo;
import '../measure/measure_controller.dart' show compassHeading;
import '../measure/wmm.dart';

/// A known point: a site of the radio directory, or a point of the map.
class KnownPoint {
  final LatLng point; final String label; final ReferenceSite? site;
  const KnownPoint({required this.point,required this.label,this.site});
}

class ResectionSight {
  KnownPoint? known;
  /// Azimuth as typed or read, in degrees; true or magnetic per [magnetic].
  double? azimuth;
  bool magnetic=false;
  ResectionSight();
}

/// Narrowest angle between two sight lines, in degrees (0–90).
double crossingAngle(double az1,double az2){
  var d=(az1-az2).abs()%180;
  if(d>90)d=180-d;
  return d;
}

class ResectionController extends ChangeNotifier {
  final sights=[ResectionSight(),ResectionSight(),ResectionSight()];
  /// Sight waiting for a touch on the map.
  int? pickingIndex;
  /// Approximate position (last GPS or centre of the map): sorting by
  /// distance and the magnetic declination.
  LatLng? around;
  double? heading;
  StreamSubscription? _acc,_mag; List<double>? _gravity,_field;
  ({LatLng? centre,double radiusM})? result;

  bool get hasCompass=>heading!=null;
  double get declination{
    final p=around??sights.map((s)=>s.known?.point).whereType<LatLng>().firstOrNull;
    return p==null?0:magneticDeclination(p.latitude,p.longitude,DateTime.now().toUtc());
  }
  double? trueAzimuth(ResectionSight s)=>s.azimuth==null?null:s.magnetic?(s.azimuth!+declination+360)%360:s.azimuth!%360;

  List<({LatLng known,double azimuthDeg})> get validSights=>[
    for(final s in sights)if(s.known!=null&&trueAzimuth(s)!=null)(known:s.known!.point,azimuthDeg:trueAzimuth(s)!)];

  /// Narrowest crossing among the valid sights; null with fewer than two.
  double? get narrowestAngle{
    final v=validSights; if(v.length<2)return null;
    double? best;
    for(var i=0;i<v.length;i++){for(var j=i+1;j<v.length;j++){
      final a=crossingAngle(v[i].azimuthDeg,v[j].azimuthDeg);
      if(best==null||a<best)best=a;
    }}
    return best;
  }
  bool get poorGeometry=>(narrowestAngle??90)<30;

  void startCompass(){
    if(_acc!=null)return;
    try{
      _acc=accelerometerEventStream().listen((e){_gravity=[e.x,e.y,e.z];_update();},onError:(_){});
      _mag=magnetometerEventStream().listen((e){_field=[e.x,e.y,e.z];_update();},onError:(_){});
    }catch(_){/* no sensor: typed azimuths */}
  }
  void _update(){
    final g=_gravity,f=_field; if(g==null||f==null)return;
    final h=compassHeading(g,f); if(h!=null){heading=h;notifyListeners();}
  }
  void stopCompass(){_acc?.cancel();_mag?.cancel();_acc=_mag=null;_gravity=_field=null;heading=null;}

  /// The compass reading becomes the azimuth of the sight (magnetic).
  void takeCompass(int i){
    final h=heading; if(h==null)return;
    sights[i]..azimuth=double.parse(h.toStringAsFixed(0))..magnetic=true;
    result=null; notifyListeners();
  }
  void setKnown(int i,KnownPoint? k){sights[i].known=k;pickingIndex=null;result=null;notifyListeners();}
  void setAzimuth(int i,double? v){sights[i].azimuth=v;result=null;notifyListeners();}
  void setMagnetic(int i,bool v){sights[i].magnetic=v;result=null;notifyListeners();}
  void pick(int? i){pickingIndex=i;notifyListeners();}

  ({LatLng? centre,double radiusM})? compute(){
    final v=validSights;
    result=v.length<2?null:resection(v);
    notifyListeners();
    return result;
  }

  void reset(){for(final s in sights){s.known=null;s.azimuth=null;s.magnetic=false;}result=null;pickingIndex=null;notifyListeners();}

  @override void dispose(){stopCompass();super.dispose();}
}

/// Sites of the directory sorted by distance from [around], filtered by the
/// text (name, callsign, description) and the kinds kept.
List<({ReferenceSite site,double? distanceM,double? bearingDeg})> resectionCandidates(Iterable<ReferenceSite> sites,
    {LatLng? around,String query='',bool highPoints=true,bool relays=true}){
  final q=query.trim().toLowerCase();
  final out=[
    for(final s in sites)
      if(((s.isHighPoint&&highPoints)||(s.isRelay&&relays))&&(q.isEmpty||
          s.name.toLowerCase().contains(q)||(s.callsign?.toLowerCase().contains(q)??false)||(s.description?.toLowerCase().contains(q)??false)))
        (site:s,distanceM:around==null?null:geo.distanceM(around,LatLng(s.lat,s.lon)),bearingDeg:around==null?null:geo.bearingDeg(around,LatLng(s.lat,s.lon))),
  ];
  out.sort((a,b)=>a.distanceM==null||b.distanceM==null?a.site.name.compareTo(b.site.name):a.distanceM!.compareTo(b.distanceM!));
  return out;
}

/// Lines drawn on the map: from each known point towards the operator
/// (opposite of the azimuth measured).
List<(LatLng,LatLng)> resectionLines(ResectionController c,{double lengthM=30000}){
  return [for(final s in c.validSights)(s.known,geo.destination(s.known,lengthM,(s.azimuthDeg+180)%360))];
}
