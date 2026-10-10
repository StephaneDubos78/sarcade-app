import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../measure/measure_controller.dart' show compassHeading;
import '../measure/wmm.dart';
import '../../services/location_service.dart';
import '../../services/sarcade_api.dart';
import '../map/drawing/geometry.dart';
import '../routes/route_models.dart';
import '../routes/routes_controller.dart';
import '../../l10n/strings.dart';
import 'road_graph_service.dart';

enum NavState{idle,computing,active,arrived}

/// Navigation to a designated point (note « Navigation »): itinerary by
/// car, on foot or off-road computed by the server (Valhalla, closed roads
/// avoided), straight line when the engine cannot be reached. The itinerary
/// is shared with the PCO (remaining distance and estimated arrival).
class NavigationController extends ChangeNotifier {
  final SarcadeApi api; final RoutesController routes; final LocationService location; final String eventId;
  /// Road graph for itineraries computed on the device (level 3).
  final RoadGraphService? graphs;
  NavigationController({required this.api,required this.routes,required this.location,required this.eventId,this.graphs});

  NavState state=NavState.idle;
  String mode='car'; String label=''; LatLng? destination;
  Itinerary? itinerary; double remaining=0; DateTime? eta; LatLng? position;
  /// Up to two variants, shown in grey; the operator taps the one he prefers.
  List<Itinerary> alternatives=const [];
  /// GPS course (degrees from true north) and speed (m/s) of the last fix.
  double? course; double? speedMs;
  /// True heading of the device from the compass (follow mode, stationary).
  double? compassTrue;
  StreamSubscription<AccelerometerEvent>? _acc; StreamSubscription<MagnetometerEvent>? _mag;
  List<double>? _gravity, _field;
  /// Message when the engine is unavailable or no itinerary exists.
  String? notice;
  String? _sharedId; StreamSubscription<Position>? _gps; DateTime _lastShare=DateTime.fromMillisecondsSinceEpoch(0);

  bool get isActive=>state==NavState.active||state==NavState.computing;

  /// [mode]: car, foot, offroad, or straight (line and bearing only).
  Future<void> start(LatLng to,String toLabel,String navMode) async {
    await _stopGps();
    destination=to; label=toLabel; mode=navMode; notice=null; _sharedId=null; alternatives=const [];
    state=NavState.computing; notifyListeners();
    final here=await location.current();
    if(here==null){state=NavState.idle;notice='no_position';notifyListeners();return;}
    position=LatLng(here.latitude,here.longitude);
    itinerary=await _compute(position!,to,withAlternatives:true);
    _update(position!);
    state=NavState.active;
    notifyListeners();
    await _share(force:true);
    _gps=location.positions().listen((p){
      if(p.speed.isFinite&&p.speed>=0)speedMs=p.speed;
      if(p.heading.isFinite&&p.heading>=0&&(p.speed.isFinite&&p.speed>1.5))course=p.heading;
      _update(LatLng(p.latitude,p.longitude));
    },onError:(_){});
  }

  Future<Itinerary> _compute(LatLng from,LatLng to,{bool withAlternatives=false}) async {
    final straightMode=mode=='straight';
    if(!straightMode){
      // The server first: finer instructions, closed roads up to date.
      try{
        final j=await api.routing(eventId,[[from.latitude,from.longitude],[to.latitude,to.longitude]],mode,
          alternatives:withAlternatives?2:0);
        final main=Itinerary.fromJson(j);
        if(withAlternatives)alternatives=distinctAlternatives(main,alternativesFromJson(j));
        return main;
      }on SarcadeHttpException catch(e){
        notice=e.statusCode==422?'no_route':'engine_unavailable';
      }catch(_){
        notice='engine_unavailable';
      }
      // Server unreachable or without engine: computed on the device.
      final graph=graphs?.graph;
      if(graph!=null&&notice=='engine_unavailable'){
        final closed=[for(final c in routes.closures) if(c.active&&c.points.length>1) c.points];
        if(withAlternatives){
          final both=graph.routeWithAlternatives(from,to,mode,closures:closed,t:S.t);
          if(both!=null){notice='on_device';alternatives=both.alternatives;return both.main;}
        }else{
          final local=graph.route(from,to,mode,closures:closed,t:S.t);
          if(local!=null){notice='on_device';return local;}
        }
        notice='no_route';
      }
    }
    return Itinerary.straightLine(from,to,straightMode?'foot':mode);
  }

  void _update(LatLng p){
    position=p;
    final it=itinerary, dest=destination;
    if(it==null||dest==null)return;
    remaining=it.straight?distanceM(p,dest):remainingM(it.geometry,p);
    if(!it.straight&&state==NavState.active)_rerouteIfOff(p,it);
    final speed=it.lengthM>0&&it.durationS>0?it.lengthM/it.durationS:1.2;
    eta=DateTime.now().toUtc().add(Duration(seconds:(remaining/speed).round()));
    if(state==NavState.active&&distanceM(p,dest)<=arrivalRadiusM){
      state=NavState.arrived;
      _share(force:true,status:'arrived');
      _stopGps();
    }else{
      _share();
    }
    notifyListeners();
  }

  DateTime _lastReroute=DateTime.fromMillisecondsSinceEpoch(0); bool _rerouting=false;

  /// Automatic new itinerary when the operator leaves the planned one by
  /// more than 60 m (at most every 30 s).
  void _rerouteIfOff(LatLng p,Itinerary it){
    if(_rerouting||DateTime.now().difference(_lastReroute).inSeconds<30)return;
    var best=double.infinity;
    for(final q in it.geometry){final d=distanceM(p,q);if(d<best)best=d;}
    if(best<60)return;
    _rerouting=true; _lastReroute=DateTime.now();
    final dest=destination!;
    _compute(p,dest).then((fresh){itinerary=fresh;alternatives=const [];notifyListeners();}).whenComplete(()=>_rerouting=false);
  }

  /// The operator chose a variant: it becomes the itinerary followed, the
  /// previous one becomes a variant.
  void chooseAlternative(int index){
    final it=itinerary;
    if(it==null||index<0||index>=alternatives.length)return;
    final chosen=alternatives[index];
    alternatives=[for(var i=0;i<alternatives.length;i++) i==index?it:alternatives[i]];
    itinerary=chosen;
    if(position!=null)_update(position!);
    _share(force:true);
    notifyListeners();
  }

  /// Compass of the follow mode when the operator does not move (phones).
  void startCompass(){
    if(_acc!=null)return;
    try{
      _acc=accelerometerEventStream().listen((e){_gravity=[e.x,e.y,e.z];_updateHeading();},onError:(_){});
      _mag=magnetometerEventStream().listen((e){_field=[e.x,e.y,e.z];_updateHeading();},onError:(_){});
    }catch(_){/* no sensor on this device */}
  }

  void _updateHeading(){
    final g=_gravity, f=_field, p=position;
    if(g==null||f==null)return;
    final m=compassHeading(g,f);
    if(m==null)return;
    final decl=p==null?0.0:magneticDeclination(p.latitude,p.longitude,DateTime.now());
    final next=(m+decl+360)%360;
    // Small changes are not worth a new frame of the map.
    if(compassTrue!=null&&((next-compassTrue!+540)%360-180).abs()<3)return;
    compassTrue=next;
    notifyListeners();
  }

  void stopCompass(){_acc?.cancel();_mag?.cancel();_acc=null;_mag=null;compassTrue=null;}

  /// Bearing to the destination, for the straight-line mode.
  double? get bearing=>position==null||destination==null?null:bearingDeg(position!,destination!);

  /// Next instruction of the itinerary from the current position.
  String? get nextInstruction{
    final it=itinerary, p=position;
    if(it==null||p==null||it.maneuvers.isEmpty)return null;
    var best=0; var bestD=double.infinity;
    for(var i=0;i<it.geometry.length;i++){final d=distanceM(p,it.geometry[i]);if(d<bestD){bestD=d;best=i;}}
    for(final m in it.maneuvers){if(m.beginIndex>best)return m.instruction;}
    return it.maneuvers.last.instruction;
  }

  /// Shared at start, then every 30 s at most, and at arrival or cancel.
  Future<void> _share({bool force=false,String status='active'}) async {
    final it=itinerary, dest=destination;
    if(it==null||dest==null)return;
    final now=DateTime.now();
    if(!force&&now.difference(_lastShare).inSeconds<30)return;
    _lastShare=now;
    try{
      _sharedId=await routes.shareItinerary(id:_sharedId,mode:mode=='straight'?'foot':mode,destination:dest,label:label,
        itinerary:it,remainingM:remaining,eta:eta??now.toUtc(),status:status);
    }catch(_){/* kept in the Outbox */}
  }

  Future<void> cancel() async {
    if(state==NavState.active)await _share(force:true,status:'cancelled');
    await _stopGps();
    stopCompass();
    state=NavState.idle; itinerary=null; destination=null; notice=null; alternatives=const []; course=null;
    notifyListeners();
  }

  Future<void> _stopGps() async {await _gps?.cancel();_gps=null;}

  @override void dispose(){_gps?.cancel();stopCompass();super.dispose();}
}
