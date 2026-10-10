import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import '../../services/sarcade_api.dart';
import '../map/drawing/geometry.dart';
import '../routes/route_models.dart';
import '../routes/routes_controller.dart';

enum NavState{idle,computing,active,arrived}

/// Navigation to a designated point (note « Navigation »): itinerary by
/// car, on foot or off-road computed by the server (Valhalla, closed roads
/// avoided), straight line when the engine cannot be reached. The itinerary
/// is shared with the PCO (remaining distance and estimated arrival).
class NavigationController extends ChangeNotifier {
  final SarcadeApi api; final RoutesController routes; final LocationService location; final String eventId;
  NavigationController({required this.api,required this.routes,required this.location,required this.eventId});

  NavState state=NavState.idle;
  String mode='car'; String label=''; LatLng? destination;
  Itinerary? itinerary; double remaining=0; DateTime? eta; LatLng? position;
  /// Message when the engine is unavailable or no itinerary exists.
  String? notice;
  String? _sharedId; StreamSubscription<Position>? _gps; DateTime _lastShare=DateTime.fromMillisecondsSinceEpoch(0);

  bool get isActive=>state==NavState.active||state==NavState.computing;

  /// [mode]: car, foot, offroad, or straight (line and bearing only).
  Future<void> start(LatLng to,String toLabel,String navMode) async {
    await _stopGps();
    destination=to; label=toLabel; mode=navMode; notice=null; _sharedId=null;
    state=NavState.computing; notifyListeners();
    final here=await location.current();
    if(here==null){state=NavState.idle;notice='no_position';notifyListeners();return;}
    position=LatLng(here.latitude,here.longitude);
    itinerary=await _compute(position!,to);
    _update(position!);
    state=NavState.active;
    notifyListeners();
    await _share(force:true);
    _gps=location.positions().listen((p){_update(LatLng(p.latitude,p.longitude));},onError:(_){});
  }

  Future<Itinerary> _compute(LatLng from,LatLng to) async {
    final straightMode=mode=='straight';
    if(!straightMode){
      try{
        return Itinerary.fromJson(await api.routing(eventId,[[from.latitude,from.longitude],[to.latitude,to.longitude]],mode));
      }on SarcadeHttpException catch(e){
        notice=e.statusCode==422?'no_route':'engine_unavailable';
      }catch(_){
        notice='engine_unavailable';
      }
    }
    return Itinerary.straightLine(from,to,straightMode?'foot':mode);
  }

  void _update(LatLng p){
    position=p;
    final it=itinerary, dest=destination;
    if(it==null||dest==null)return;
    remaining=it.straight?distanceM(p,dest):remainingM(it.geometry,p);
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
    state=NavState.idle; itinerary=null; destination=null; notice=null;
    notifyListeners();
  }

  Future<void> _stopGps() async {await _gps?.cancel();_gps=null;}

  @override void dispose(){_gps?.cancel();super.dispose();}
}
