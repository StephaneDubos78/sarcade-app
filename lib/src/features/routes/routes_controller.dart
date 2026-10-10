import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../services/sarcade_api.dart';
import 'route_models.dart';

/// Routes, waypoints, passages and road closures of the event: kept on the
/// device, changed locally then sent through the Outbox (ADR-001: one object
/// per waypoint, last change wins per object).
class RoutesController extends ChangeNotifier {
  final SarcadeApi api; final LocalStore store; final OfflineSyncService sync;
  final String eventId, actorId;
  final _uuid=const Uuid();
  final Map<String,Map<String,dynamic>> _objects={};

  RoutesController({required this.api,required this.store,required this.sync,required this.eventId,required this.actorId}){
    for(final j in store.routeObjects(eventId)){_objects[j['id'] as String]=j;}
  }

  Iterable<Map<String,dynamic>> _ofKind(String kind)=>_objects.values.where((j)=>j['kind']==kind&&j['deleted']!=true);
  List<RoutePlan> get routes=>_ofKind('route').map(RoutePlan.new).toList()..sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<Waypoint> get waypoints=>_ofKind('route_waypoint').map(Waypoint.new).toList();
  List<Map<String,dynamic>> get passages=>_ofKind('route_passage').toList();
  List<RoadClosure> get closures=>_ofKind('road_closure').map(RoadClosure.new).toList();
  RoutePlan? route(String id){final j=_objects[id];return j==null||j['kind']!='route'||j['deleted']==true?null:RoutePlan(j);}
  List<Waypoint> ordered(RoutePlan r)=>orderedWaypoints(r,waypoints);

  /// Server state: routes (with waypoints and passages) and road closures.
  Future<void> refresh() async {
    try{
      final list=await api.routes(eventId);
      for(final r in list){
        final route=Map<String,dynamic>.from(r)..remove('waypoints')..remove('passages')..remove('total_length_m');
        await _remote('route',route);
        for(final w in (r['waypoints'] as List?)??const []){await _remote('route_waypoint',Map<String,dynamic>.from(w as Map));}
        for(final p in (r['passages'] as List?)??const []){await _remote('route_passage',Map<String,dynamic>.from(p as Map));}
      }
      for(final c in await api.roadClosures(eventId)){await _remote('road_closure',c);}
      notifyListeners();
    }catch(_){/* offline: objects known on the device */}
  }

  /// Change from the feed or the realtime channel. A local change still in
  /// the Outbox keeps priority until the server has ruled on it.
  Future<void> applyRemote(String kind,Map<String,dynamic> payload) async {
    if(!routeObjectKinds.contains(kind))return;
    await _remote(kind,payload);
    notifyListeners();
  }

  Future<void> _remote(String kind,Map<String,dynamic> p) async {
    final id=p['id'];
    if(id is! String||p['event_id']!=eventId||sync.isPending(id))return;
    if(p['deleted']==true){_objects.remove(id);await store.deleteRouteObject(id);return;}
    final j={...p,'kind':kind};
    _objects[id]=j;
    await store.saveRouteObject(j);
  }

  String _now()=>DateTime.now().toUtc().toIso8601String();

  Future<void> _save(String kind,Map<String,dynamic> j,{required bool isNew}) async {
    final payload={...j,'kind':kind,'event_id':eventId,'updated_by':actorId,'updated_at':_now()};
    if(isNew)payload['created_by']=actorId;
    _objects[payload['id'] as String]=payload;
    await store.saveRouteObject(payload);
    notifyListeners();
    await sync.queue(objectId:payload['id'] as String,objectType:kind,action:isNew?'create':'update',payload:payload);
  }

  Future<void> _delete(String kind,String id) async {
    _objects.remove(id);
    await store.deleteRouteObject(id);
    notifyListeners();
    await sync.queue(objectId:id,objectType:kind,action:'delete',payload:{'id':id,'event_id':eventId,'updated_by':actorId,'updated_at':_now()});
  }

  // --- Routes ---------------------------------------------------------------

  Future<RoutePlan> createRoute({required String name,required String profile,required String legMode,int color=0xFF1E88E5}) async {
    final j={'id':_uuid.v4(),'name':name,'profile':profile,'default_leg_mode':legMode,'status':'draft','color':color,'point_order':<String>[]};
    await _save('route',j,isNew:true);
    return RoutePlan(_objects[j['id']]!);
  }

  Future<void> updateRoute(RoutePlan r,Map<String,dynamic> changes)=>_save('route',{...r.json,...changes},isNew:false);

  Future<void> deleteRoute(RoutePlan r) async {
    for(final w in ordered(r)){_objects.remove(w.id);await store.deleteRouteObject(w.id);}
    await _delete('route',r.id);
  }

  Future<void> _setOrder(RoutePlan r,List<String> order)=>
    _save('route',{...r.json,'point_order':order,'base_point_order':r.pointOrder},isNew:false);

  // --- Waypoints ------------------------------------------------------------

  Future<Waypoint> addWaypoint(RoutePlan r,LatLng point) async {
    final existing=ordered(r);
    final mode=r.defaultLegMode;
    final j={'id':_uuid.v4(),'route_id':r.id,'name':nextWaypointName(existing),'type':nextWaypointType(existing.length),
      'lat':point.latitude,'lon':point.longitude,'comment':'','radius_m':defaultRadiusM,'leg_mode':mode,
      // Computed by the server when online (Valhalla), even if posed offline.
      'leg_needs_routing':mode=='paths'&&existing.isNotEmpty,'leg_geometry':null};
    await _save('route_waypoint',j,isNew:true);
    await _setOrder(route(r.id)??r,[...existing.map((w)=>w.id),j['id'] as String]);
    _requestLegs(r);
    return Waypoint(_objects[j['id']]!);
  }

  Future<void> updateWaypoint(Waypoint w,Map<String,dynamic> changes) async {
    final moved=changes.containsKey('lat')||changes.containsKey('lon');
    final modeChanged=changes.containsKey('leg_mode');
    final j={...w.json,...changes};
    if((moved||modeChanged)&&j['leg_mode']=='paths'){j['leg_needs_routing']=true;j['leg_geometry']=null;}
    if(j['leg_mode']!='paths'){j['leg_needs_routing']=false;}
    await _save('route_waypoint',j,isNew:false);
    final r=route(w.routeId);
    if(r!=null&&moved){
      // The leg leaving this point changes too.
      final list=ordered(r);
      final i=list.indexWhere((x)=>x.id==w.id);
      if(i>=0&&i+1<list.length&&list[i+1].legMode=='paths'){
        await _save('route_waypoint',{...list[i+1].json,'leg_needs_routing':true,'leg_geometry':null},isNew:false);
      }
      _requestLegs(r);
    }
  }

  Future<void> deleteWaypoint(Waypoint w) async {
    final r=route(w.routeId);
    await _delete('route_waypoint',w.id);
    if(r!=null)await _setOrder(r,r.pointOrder.where((id)=>id!=w.id).toList());
  }

  Future<void> moveWaypoint(Waypoint w,int delta) async {
    final r=route(w.routeId);
    if(r==null)return;
    final order=ordered(r).map((x)=>x.id).toList();
    final i=order.indexOf(w.id), j=i+delta;
    if(i<0||j<0||j>=order.length)return;
    order..removeAt(i)..insert(j,w.id);
    await _setOrder(r,order);
  }

  /// Legs « along paths » are computed by the server; asked at once when
  /// online, else the server computes them by itself later.
  void _requestLegs(RoutePlan r){
    api.computeLegs(eventId,r.id).then((_)=>sync.syncNow()).catchError((_){});
  }

  // --- Passages -------------------------------------------------------------

  Future<void> recordPassage(Waypoint w,{required String mode,String? deviceId,String? teamId}) async {
    await _save('route_passage',{'id':_uuid.v4(),'route_id':w.routeId,'waypoint_id':w.id,'device_id':deviceId??actorId,
      'team_id':teamId,'mode':mode,'cancelled':false,'time':_now()},isNew:true);
  }

  Future<void> cancelPassage(Map<String,dynamic> passage)=>_save('route_passage',{...passage,'cancelled':true},isNew:false);

  // --- Road closures (PCO) ----------------------------------------------------

  Future<void> createClosure(String label,List<LatLng> points)=>
    _save('road_closure',{'id':_uuid.v4(),'label':label,'points':lineJson(points),'active':true},isNew:true);

  Future<void> setClosureActive(RoadClosure c,bool active)=>_save('road_closure',{...c.json,'active':active},isNew:false);

  // --- Shared itinerary ---------------------------------------------------------

  Future<String> shareItinerary({String? id,required String mode,required LatLng destination,required String label,
      required Itinerary itinerary,required double remainingM,required DateTime eta,String status='active'}) async {
    final itineraryId=id??_uuid.v4();
    await _save('itinerary',{'id':itineraryId,'device_id':actorId,'mode':mode,'status':status,
      'destination':{'lat':destination.latitude,'lon':destination.longitude,'label':label},
      'geometry':lineJson(itinerary.geometry),'length_m':itinerary.lengthM,'remaining_m':remainingM,
      'eta':eta.toUtc().toIso8601String()},isNew:id==null);
    return itineraryId;
  }
}
