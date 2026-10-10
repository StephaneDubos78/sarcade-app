import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:uuid/uuid.dart';

import '../../models/comm_group.dart';
import '../../models/poi.dart';
import '../../models/message.dart';
import '../../models/position.dart';
import '../../models/reference_site.dart';
import '../messages/messages_page.dart';
import '../logbook/logbook_page.dart';
import '../files/files_page.dart';
import 'drawing/drawing_controller.dart';
import 'drawing/drawing_layers.dart';
import 'drawing/drawing_toolbar.dart';
import 'drawing/geometry.dart';
import 'drawing/hit_test.dart';
import 'drawing/import_formats.dart';
import 'drawing/map_feature.dart';
import '../../services/notification_service.dart';
import '../../services/location_service.dart';
import '../../services/realtime_service.dart';
import '../../services/sarcade_api.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../platform/platform_services.dart';
import '../../l10n/strings.dart';
import '../../operations/event_settings.dart';
import '../../operations/operations_service.dart';
import '../../operations/operations_widgets.dart';
import '../../operations/tracking_service.dart';
import '../navigation/navigation_controller.dart';
import '../basemaps/basemap_models.dart';
import '../basemaps/basemap_sheet.dart';
import '../weather/weather_page.dart';
import '../measure/coordinates.dart';
import '../measure/external_maps.dart';
import '../measure/measure_controller.dart';
import '../measure/measure_widgets.dart';
import '../navigation/navigation_widgets.dart';
import '../routes/route_models.dart';
import '../routes/routes_controller.dart';
import '../routes/routes_layers.dart';
import '../routes/routes_panel.dart';

class OperationalMapPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,deviceId,tileUrl,tileAttribution; final LocalStore store; final VoidCallback? onSettings;
  /// Operator settings sent with the heartbeat (APRS callsign and consent).
  final String callsign; final bool aprsTxConsent;
  /// Platform name sent to the server (« windows », « android », « web »…).
  final String platform;
  const OperationalMapPage({super.key,required this.api,required this.eventId,required this.deviceId,required this.store,required this.tileUrl,required this.tileAttribution,this.onSettings,
    this.callsign='',this.aprsTxConsent=false,this.platform='unknown'});
  @override State<OperationalMapPage> createState()=>_OperationalMapPageState();
}

class _OperationalMapPageState extends State<OperationalMapPage> {
  final _map=MapController(); final _realtime=RealtimeService(); final _location=LocationService(); final _notifications=NotificationService(); final _uuid=const Uuid();
  final Map<String,SarcadePosition> _positions={}; final Map<String,SarcadePoi> _pois={}; final Map<String,ReferenceSite> _references={};
  StreamSubscription? _rtSub; Timer? _syncUiTimer; String _status=S.t('status.connecting'); bool _showPanel=true; bool _showReferencePanel=false; bool _showHighPoints=true; bool _showRelays=true; String _referenceQuery=''; String? _selectedDevice; ReferenceSite? _selectedReference; List<SarcadePosition> _trace=[]; bool _traceLoading=false; late final OfflineSyncService _sync; bool _layoutInitialized=false;
  late final DrawingController _drawing; bool _drawingTools=false; final _mapKey=GlobalKey();
  late final TrackingService _tracking; late final OperationsService _ops; bool _updatePageShown=false;
  late final RoutesController _routes; late final NavigationController _nav;
  List<Basemap> _catalog=builtInBasemaps;
  /// APRS stations followed by the event (the server only sends those).
  bool _showAprs=true;
  late final MeasureController _measure; bool _pickingOrigin=false;
  CoordFormat get _coordFormat=>coordFormatFrom(widget.store.preference('coord_format'));
  bool _showRoutesPanel=false; String? _selectedRouteId, _drawingRouteId; bool _drawingClosure=false; final List<LatLng> _closureDraft=[];
  final List<Offset> _stroke=[];

  // Phones get the map full width: side panels start closed and open as overlays.
  static const _compactWidth=600.0;
  @override void didChangeDependencies(){super.didChangeDependencies();if(!_layoutInitialized){_layoutInitialized=true;if(MediaQuery.sizeOf(context).width<_compactWidth)_showPanel=false;}}

  @override void initState(){super.initState();_notifications.initialize();_sync=OfflineSyncService(api:widget.api,store:widget.store,eventId:widget.eventId,onRemoteChange:_onRemoteChange);_initDrawing();_loadLocal();_initRoutes();_initMeasure();_sync.start();_initOperations();_loadBasemaps();_syncUiTimer=Timer.periodic(const Duration(seconds:2),(_){if(mounted)setState((){});});_start();}
  bool _validPosition(SarcadePosition p){
    final t=p.time.toUtc(), now=DateTime.now().toUtc();
    return t.isAfter(DateTime.utc(2020)) && t.isBefore(now.add(const Duration(days:1)));
  }
  void _loadLocal(){for(final j in widget.store.positions()){final p=SarcadePosition.fromJson(j);if(p.eventId==widget.eventId&&_validPosition(p))_positions[p.deviceId]=p;}for(final j in widget.store.pois()){final p=SarcadePoi.fromJson(j);if(p.eventId==widget.eventId)_pois[p.id]=p;}for(final j in widget.store.references()){final p=ReferenceSite.fromJson(j);if(p.status=='active')_references[p.id]=p;}}
  Future<void> _start() async {
    try {
      final data=await Future.wait([widget.api.latestPositions(widget.eventId),widget.api.pois(widget.eventId)]);
      for(final p in data[0] as List<SarcadePosition>){if(_validPosition(p)){_positions[p.deviceId]=p;widget.store.cachePosition(p.toJson());}}
      for(final p in data[1] as List<SarcadePoi>){_pois[p.id]=p;}
      try{await _refreshReferences(silent:true);}catch(_){}
      _realtime.connect(widget.api.websocketUri(widget.eventId));
      _rtSub=_realtime.events.listen(_onRealtime,onError:(_){if(mounted)setState(()=>_status=S.t('status.realtimeUnavailable'));});
      if(mounted){setState(()=>_status=S.t('status.connected'));WidgetsBinding.instance.addPostFrameCallback((_)=>_fitOperators());}
    } catch(e){if(mounted)setState(()=>_status=S.t('status.offline'));}
  }
  void _onRealtime(RealtimeEvent e){
    if(e.type=='position.updated'){final p=SarcadePosition.fromJson(e.data);if(_validPosition(p)){widget.store.cachePosition(p.toJson());if(mounted)setState((){_positions[p.deviceId]=p;if(_selectedDevice==p.deviceId)_trace.add(p);});}}
    if(e.type=='poi.created'){final p=SarcadePoi.fromJson(e.data);widget.store.cachePoi(e.data);setState(()=>_pois[p.id]=p);}
    if(e.type=='message.created'){_receiveMessage(e.data);}
    if(e.type=='map_feature.upserted'||e.type=='map_feature.deleted'){_applyRemoteFeature(e.data,persist:true);}
    if(e.type=='ack.created'){widget.store.cacheAck(e.data);if(mounted)setState((){});}
    if(e.type=='group.upserted'&&!_sync.isPending('${e.data['id']}')){widget.store.saveGroup(e.data);}
    final kind=e.type.split('.').first;
    if(routeObjectKinds.contains(kind)&&(e.type.endsWith('.upserted')||e.type.endsWith('.deleted'))){_routes.applyRemote(kind,e.data);}
    if(e.type=='weather.alert'){
      final text='${e.data['summary']??e.data['color']??''}';
      _notifications.message(title:'SARCADE · ${S.t('weather.menu')}',body:S.t('weather.alert',{'text':text}),priority:'urgent');
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration:const Duration(seconds:10),content:Text(S.t('weather.alert',{'text':text})),
          action:SnackBarAction(label:S.t('weather.menu'),onPressed:()=>_openWeather())));
      }
    }
    if(e.type=='group.deleted'){widget.store.deleteGroup('${e.data['id']}');}
    // PCO settings changed or event closed: the heartbeat brings the new state.
    if(e.type=='event.settings.updated'||e.type=='event.closed'){unawaited(_ops.beat());}
  }

  Future<void> _receiveMessage(Map<String,dynamic> data) async {
    final m=SarcadeMessage.fromJson(data);
    await widget.store.cacheMessage(data);
    final groups={for(final j in widget.store.groups(widget.eventId)) j['id'] as String:CommGroup.fromJson(j)};
    final addressed=addressedTo(m.recipientIds,widget.deviceId,groups);
    if(addressed && m.senderId!=widget.deviceId){
      final existing=widget.store.acks().map(SarcadeAck.fromJson).any((a)=>a.messageId==m.id&&a.actorId==widget.deviceId&&a.status=='received');
      if(!existing){
        final ack=SarcadeAck(id:_uuid.v4(),eventId:widget.eventId,messageId:m.id,actorId:widget.deviceId,status:'received',time:DateTime.now().toUtc());
        await widget.store.cacheAck(ack.toJson());
        await _sync.queue(objectId:ack.id,objectType:'ack',payload:ack.toJson());
      }
      await _notifications.message(title:'SARCADE · ${S.t('priority.${m.priority}')} · ${m.senderId}',body:m.body,priority:m.priority);
    }
    if(mounted)setState((){});
  }

  /// Base map catalog: cached, then from the server (custom layers, offline packages).
  Future<void> _loadBasemaps() async {
    final cached=widget.store.cachedJson('basemaps');
    if(cached!=null&&cached['items'] is List){
      _catalog=mergeCatalog([for(final j in cached['items'] as List) if(j is Map) Basemap.fromJson(Map<String,dynamic>.from(j))]);
    }
    try{
      final list=await widget.api.basemaps();
      await widget.store.cacheJson('basemaps',{'items':list});
      if(mounted)setState(()=>_catalog=mergeCatalog(list.map(Basemap.fromJson).toList()));
    }catch(_){/* offline: cached or built-in catalog */}
  }

  Basemap get _basemap=>pickBasemap(_catalog,operatorChoice:widget.store.preference('basemap:${widget.eventId}'),eventDefault:_ops.settings.basemap);
  bool get _preferOffline=>widget.store.preference('basemap_offline')=='1';
  String get _tileUrl=>_basemap.tileUrl(widget.api.baseUrl,preferOffline:_preferOffline)??widget.tileUrl;

  void _chooseBasemap()=>showBasemapSheet(context,catalog:_catalog,current:_basemap,eventDefault:_ops.settings.basemap,
    preferOffline:_preferOffline,
    onChoose:(id) async {await widget.store.setPreference('basemap:${widget.eventId}',id);if(mounted)setState((){});},
    onPreferOffline:(v) async {await widget.store.setPreference('basemap_offline',v?'1':null);if(mounted)setState((){});});

  void _openWeather({({double lat,double lon,String label})? point}){
    final mine=_positions[widget.deviceId];
    Navigator.push(context,MaterialPageRoute(builder:(_)=>WeatherPage(api:widget.api,store:widget.store,eventId:widget.eventId,
      actorId:widget.deviceId,lowBandwidth:_ops.settings.lowBandwidth,point:point,
      fallback:mine==null?null:(lat:mine.lat,lon:mine.lon))));
  }

  /// Long press on the map: navigate to the point or see its weather.
  Future<void> _onLongPress(LatLng point) async {
    final label=S.t('nav.point');
    final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.straighten),title:Text(S.t('measure.here')),onTap:()=>Navigator.pop(c,'measure')),
      ListTile(leading:const Icon(Icons.directions),title:Text(S.t('nav.goHere')),onTap:()=>Navigator.pop(c,'nav')),
      ListTile(leading:const Icon(Icons.open_in_new),title:Text(S.t('ext.open')),onTap:()=>Navigator.pop(c,'ext')),
      ListTile(leading:const Icon(Icons.cloud_outlined),title:Text(S.t('weather.here')),onTap:()=>Navigator.pop(c,'weather')),
    ])));
    if(choice=='measure')await _measureTo(point,label);
    if(choice=='ext'&&mounted)await openInOtherApp(context,point,label);
    if(choice=='nav')await _navigateTo(point,label);
    if(choice=='weather')_openWeather(point:(lat:point.latitude,lon:point.longitude,label:label));
  }

  void _initMeasure(){
    _measure=MeasureController(location:_location);
    _measure.addListener(_onRoutesChanged);
  }

  Future<void> _measureTo(LatLng point,String label) async {
    await _measure.start(point,label);
    _measure.startCompass();
  }

  Future<void> _chooseOrigin() async {
    final others=_positions.values.where((p)=>p.deviceId!=widget.deviceId).toList()..sort((a,b)=>a.label.compareTo(b.label));
    final choice=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('measure.chooseOrigin')),children:[
      SimpleDialogOption(onPressed:()=>Navigator.pop(c,'mine'),child:Text(S.t('measure.originMine'))),
      SimpleDialogOption(onPressed:()=>Navigator.pop(c,'point'),child:Text(S.t('measure.originPoint'))),
      for(final p in others)SimpleDialogOption(onPressed:()=>Navigator.pop(c,'dev:${p.deviceId}'),child:Text(p.label)),
    ]));
    if(choice==null||!mounted)return;
    if(choice=='mine'){final t=_measure.target;if(t!=null)await _measure.start(t,_measure.targetLabel);return;}
    if(choice=='point'){setState(()=>_pickingOrigin=true);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('measure.pickOrigin'))));return;}
    final p=_positions[choice.substring(4)];
    if(p!=null)_measure.setOrigin(MeasureOrigin(point:LatLng(p.lat,p.lon),label:p.label,accuracyM:p.accuracyM,time:p.time));
  }

  Future<void> _savePoi() async {
    final t=_measure.target;
    if(t==null)return;
    final now=DateTime.now().toUtc();
    final poi={'id':_uuid.v4(),'event_id':widget.eventId,'kind':'designated','label':_measure.targetLabel,
      'lat':t.latitude,'lon':t.longitude,'created_at':now.toIso8601String()};
    await widget.store.cachePoi(poi);
    setState(()=>_pois[poi['id'] as String]=SarcadePoi.fromJson(poi));
    await _sync.queue(objectId:poi['id'] as String,objectType:'poi',payload:poi);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('measure.poiSaved'))));
  }

  void _sendMeasure()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,
    actorId:widget.deviceId,sync:_sync,store:widget.store,initialText:measureMessage(_measure,_coordFormat))));

  Future<void> _gotoCoordinates() async {
    final controller=TextEditingController();
    final text=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('measure.goto')),
      content:TextField(controller:controller,autofocus:true,decoration:InputDecoration(hintText:S.t('measure.gotoHint'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,controller.text),child:Text(S.t('common.ok')))],
    ));
    if(text==null||!mounted)return;
    final p=parseCoordinates(text);
    if(p==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('measure.gotoInvalid'))));return;}
    _map.move(p,15);
    await _measureTo(p,S.t('measure.coordinates'));
  }

  void _initRoutes(){
    _routes=RoutesController(api:widget.api,store:widget.store,sync:_sync,eventId:widget.eventId,actorId:widget.deviceId);
    _nav=NavigationController(api:widget.api,routes:_routes,location:_location,eventId:widget.eventId);
    _routes.addListener(_onRoutesChanged);
    _nav.addListener(_onRoutesChanged);
    _routes.refresh();
  }
  void _onRoutesChanged(){if(mounted)setState((){});}

  /// Automatic passage when the operator enters the approach radius of the
  /// next waypoint of an active route (50 m by default).
  Future<void> _checkPassages(LatLng position) async {
    for(final r in _routes.routes.where((r)=>r.status=='active')){
      final ordered=_routes.ordered(r);
      final reached=reachedWaypoint(ordered,passedWaypoints(_routes.passages,r.id,deviceId:widget.deviceId),position);
      if(reached!=null){
        await _routes.recordPassage(reached,mode:'auto');
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('routes.passageRecorded',{'name':reached.name}))));
      }
    }
  }

  Future<void> _navigateTo(LatLng point,String label) async {
    final mode=await chooseNavigationMode(context,label);
    if(mode==null)return;
    await _nav.start(point,label,mode);
    final it=_nav.itinerary;
    if(it!=null&&it.geometry.length>1)_fitPoints(it.geometry);
  }

  Future<void> _finishClosure() async {
    if(_closureDraft.length<2){setState((){_drawingClosure=false;_closureDraft.clear();});return;}
    final label=await askClosureLabel(context);
    if(label!=null&&label.trim().isNotEmpty)await _routes.createClosure(label.trim(),List<LatLng>.from(_closureDraft));
    if(mounted)setState((){_drawingClosure=false;_closureDraft.clear();});
  }

  void _initOperations(){
    final prefs=widget.store.trackingPrefs(widget.eventId);
    _tracking=TrackingService(eventId:widget.eventId,deviceId:widget.deviceId,location:_location,
      intervalS:prefs?.intervalS??30,onPosition:_sendOwnPosition);
    _ops=OperationsService(api:widget.api,store:widget.store,sync:_sync,eventId:widget.eventId,deviceId:widget.deviceId,
      platform:widget.platform,
      tracking:()=>(enabled:_tracking.enabled,intervalS:_tracking.intervalS),
      operator:()=>(callsign:widget.callsign,aprsTxConsent:widget.aprsTxConsent));
    _tracking.setInterval(_ops.settings.clampInterval(prefs?.intervalS??_ops.settings.trackingDefaultS));
    _tracking.addListener(_onOperationsChanged);
    _ops.addListener(_onOperationsChanged);
    _ops.start();
    if(prefs?.enabled==true&&!_ops.settings.eventEnded)_setTracking(true,_tracking.intervalS,silent:true);
  }

  /// Applies the PCO policy: tracking required during the event, stopped at
  /// its end, interval kept within the bounds; and the minimal version.
  void _onOperationsChanged(){
    final s=_ops.settings;
    if(s.eventEnded&&_tracking.enabled){_tracking.stop();}
    else if(s.trackingRequired&&!_tracking.enabled&&!s.eventEnded){_setTracking(true,_tracking.intervalS,silent:true);}
    final clamped=s.clampInterval(_tracking.intervalS);
    if(clamped!=_tracking.intervalS)_tracking.setInterval(clamped);
    if(_ops.update.status==UpdateStatus.required&&!_updatePageShown&&mounted){
      _updatePageShown=true;
      Navigator.of(context).push(MaterialPageRoute(builder:(_)=>UpdateRequiredPage(api:widget.api,update:_ops.update,platform:widget.platform)));
    }
    if(mounted)setState((){});
  }

  Future<void> _sendOwnPosition(SarcadePosition p) async {
    await widget.store.cachePosition(p.toJson());
    if(mounted)setState(()=>_positions[widget.deviceId]=p);
    await _sync.queue(objectId:p.id,objectType:'position',payload:p.toJson());
    await _checkPassages(LatLng(p.lat,p.lon));
  }

  Future<void> _setTracking(bool enabled,int intervalS,{bool silent=false}) async {
    _tracking.setInterval(_ops.settings.clampInterval(intervalS));
    if(enabled){
      if(!await _tracking.start()){
        if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('tracking.permission'))));
      }
    }else{
      await _tracking.stop();
    }
    await widget.store.saveTrackingPrefs(widget.eventId,_tracking.enabled,_tracking.intervalS);
    unawaited(_ops.beat());
  }

  void _openTracking()=>showTrackingSheet(context,tracking:_tracking,settings:_ops.settings,onChange:(enabled,interval)=>_setTracking(enabled,interval));

  void _fitOperators(){
    if(_positions.isEmpty)return;
    final pts=_positions.values.map((p)=>LatLng(p.lat,p.lon)).toList();
    if(pts.length==1){_map.move(pts.first,15);return;}
    var minLat=pts.first.latitude,maxLat=pts.first.latitude,minLon=pts.first.longitude,maxLon=pts.first.longitude;
    for(final p in pts){if(p.latitude<minLat)minLat=p.latitude;if(p.latitude>maxLat)maxLat=p.latitude;if(p.longitude<minLon)minLon=p.longitude;if(p.longitude>maxLon)maxLon=p.longitude;}
    _map.fitCamera(CameraFit.bounds(bounds:LatLngBounds(LatLng(minLat,minLon),LatLng(maxLat,maxLon)),padding:const EdgeInsets.all(90),maxZoom:16));
  }
  Future<void> _select(SarcadePosition p) async {setState((){_selectedDevice=p.deviceId;_traceLoading=true;_trace=[];});_map.move(LatLng(p.lat,p.lon),16);try{final h=await widget.api.positionHistory(widget.eventId,p.deviceId);if(mounted)setState(()=>_trace=h.where(_validPosition).toList());}finally{if(mounted)setState(()=>_traceLoading=false);}}
  Future<void> _refreshReferences({bool silent=false}) async {
    try{
      final refs=await widget.api.referenceSites();
      await widget.store.replaceReferences(refs.map((e)=>e.toJson()).toList());
      if(mounted)setState((){_references..clear()..addEntries(refs.map((e)=>MapEntry(e.id,e)));});
      if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('refs.updated',{'n':refs.length}))));
    }catch(e){
      if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('refs.updateFailed'))));
      rethrow;
    }
  }
  void _selectReference(ReferenceSite site){setState((){_selectedReference=site;_showReferencePanel=true;_showPanel=false;});_map.move(LatLng(site.lat,site.lon),14);}
  List<ReferenceSite> _filteredReferences(){
    final q=_referenceQuery.trim().toLowerCase();
    final rows=_references.values.where((r){
      if(r.isHighPoint&&!_showHighPoints)return false;
      if(r.isRelay&&!_showRelays)return false;
      if(q.isEmpty)return true;
      final haystack=[r.name,r.callsign??'',r.mode??'',r.subtype??'',r.rxMhz?.toString()??'',r.txMhz?.toString()??''].join(' ').toLowerCase();
      return haystack.contains(q.replaceAll(',','.'))||haystack.contains(q);
    }).toList()..sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
  }
  String _frequency(double? value)=>value==null?'-':'${value.toStringAsFixed(3)} MHz';
  String _age(DateTime t){final d=DateTime.now().toUtc().difference(t.toUtc());if(d.inSeconds<60)return '${d.inSeconds}s';if(d.inMinutes<60)return '${d.inMinutes} min';return '${d.inHours} h';}
  List<List<SarcadePosition>> _traceSegments(){
    if(_trace.length<2)return _trace.isEmpty?<List<SarcadePosition>>[]:[List<SarcadePosition>.from(_trace)];
    final ordered=List<SarcadePosition>.from(_trace)..sort((a,b)=>a.time.compareTo(b.time));
    final segments=<List<SarcadePosition>>[]; var current=<SarcadePosition>[ordered.first];
    for(var i=1;i<ordered.length;i++){
      final previous=ordered[i-1], next=ordered[i];
      final gap=next.time.toUtc().difference(previous.time.toUtc());
      if(gap>const Duration(minutes:5)){
        if(current.length>1)segments.add(current);
        current=<SarcadePosition>[next];
      }else{current.add(next);}
    }
    if(current.length>1)segments.add(current);
    return segments;
  }

  void _initDrawing(){
    final initial=<MapFeature>[];
    for(final j in widget.store.mapFeatures(widget.eventId)){
      try{initial.add(MapFeature.fromJson(j));}catch(_){/* skip an object saved by an incompatible build */}
    }
    _drawing=DrawingController(
      eventId:widget.eventId,actorId:widget.deviceId,initial:initial,
      onChanged:_onLocalFeatureChanged,
      onDeleted:_onLocalFeatureDeleted,
    );
    _drawing.addListener(_onDrawingChanged);
  }
  void _onDrawingChanged(){if(mounted)setState((){});}

  // Local edits: stored at once, then sent through the Outbox (ADR-001).
  void _onLocalFeatureChanged(MapFeature f,{required bool isNew}){
    widget.store.saveMapFeature(f.toJson());
    _sync.queue(objectId:f.id,objectType:'map_feature',action:isNew?'create':'update',payload:f.toJson());
  }

  void _onLocalFeatureDeleted(MapFeature f){
    widget.store.deleteMapFeature(f.id);
    _sync.queue(objectId:f.id,objectType:'map_feature',action:'delete',payload:{
      'id':f.id,'event_id':widget.eventId,'updated_by':widget.deviceId,'updated_at':DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _onRemoteChange(String objectType,Map<String,dynamic> payload){
    if(objectType=='map_feature')_applyRemoteFeature(payload);
    if(routeObjectKinds.contains(objectType))_routes.applyRemote(objectType,payload);
  }

  /// Server state of a map object, from the change feed or realtime.
  /// A local change still waiting in the Outbox keeps priority until the
  /// server has ruled on it; the winning state then arrives through the feed.
  void _applyRemoteFeature(Map<String,dynamic> p,{bool persist=false}){
    final id=p['id'];
    if(id is! String||p['event_id']!=widget.eventId||_sync.isPending(id))return;
    if(p['deleted']==true){
      DateTime? at;
      try{at=DateTime.parse(p['updated_at'] as String);}catch(_){}
      _drawing.removeRemote(id,at:at,by:p['updated_by'] as String?);
      if(persist)widget.store.deleteMapFeature(id);
      return;
    }
    try{
      final f=MapFeature.fromJson(p);
      _drawing.applyRemote(f);
      if(persist&&identical(_drawing.feature(id),f))widget.store.saveMapFeature(p);
    }catch(_){/* malformed or newer schema: ignored, the feed will resend */}
  }

  LatLng _globalToLatLng(Offset global){
    final box=_mapKey.currentContext?.findRenderObject() as RenderBox?;
    final local=box==null?global:box.globalToLocal(global);
    return _map.camera.screenOffsetToLatLng(local);
  }

  double _circleRadiusPx(MapFeature f){
    final cam=_map.camera;
    final center=cam.latLngToScreenOffset(f.points[0]);
    final edge=cam.latLngToScreenOffset(destination(f.points[0],f.radiusM??0,90));
    return (edge-center).distance;
  }

  Future<void> _onMapTap(TapPosition tap,LatLng point) async {
    if(_pickingOrigin){setState(()=>_pickingOrigin=false);_measure.setOrigin(MeasureOrigin(point:point,label:S.t('measure.originPoint')));return;}
    final drawingRoute=_drawingRouteId==null?null:_routes.route(_drawingRouteId!);
    if(drawingRoute!=null){await _routes.addWaypoint(drawingRoute,point);return;}
    if(_drawingClosure){setState(()=>_closureDraft.add(point));return;}
    if(_drawing.isDrawing){
      if(_drawing.tool==FeatureKind.text){
        final text=await _askText(title:S.t('map.textTitle'),initial:'');
        if(text==null||text.trim().isEmpty)return;
        _drawing.tapAt(point,label:text.trim());
      }else{
        _drawing.tapAt(point);
      }
      return;
    }
    final cam=_map.camera;
    final hit=hitTest(_drawing.features,tap.relative??cam.latLngToScreenOffset(point),cam.latLngToScreenOffset,radiusPx:_circleRadiusPx);
    _drawing.select(hit?.id);
  }

  Future<String?> _askText({required String title,required String initial}){
    final controller=TextEditingController(text:initial);
    return showDialog<String>(context:context,builder:(context)=>AlertDialog(
      title:Text(title),
      content:TextField(controller:controller,autofocus:true,textCapitalization:TextCapitalization.sentences,maxLength:80,onSubmitted:(v)=>Navigator.pop(context,v)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(context,controller.text),child:Text(S.t('common.ok'))),
      ],
    )).whenComplete(controller.dispose);
  }

  Future<void> _editSelectedLabel() async {
    final f=_drawing.selected;
    if(f==null)return;
    final text=await _askText(title:f.kind==FeatureKind.text?S.t('draw.editText'):S.t('map.objectName'),initial:f.label);
    if(text!=null)_drawing.setLabel(text);
  }

  void _onFreehandStart(DragStartDetails d){setState((){_stroke..clear()..add(d.localPosition);});}
  void _onFreehandUpdate(DragUpdateDetails d){
    // Keep a point every 4 px: smooth enough on screen, light to store and sync.
    if(_stroke.isEmpty||(d.localPosition-_stroke.last).distance>=4)setState(()=>_stroke.add(d.localPosition));
  }
  void _onFreehandEnd(DragEndDetails _){
    final cam=_map.camera;
    final pts=_stroke.map(cam.screenOffsetToLatLng).toList();
    setState(()=>_stroke.clear());
    _drawing.commitFreehand(pts);
  }

  /// Imports a GPX, KML, KMZ or GeoJSON file as map objects, then frames them.
  Future<void> _importFile() async {
    final messenger=ScaffoldMessenger.of(context);
    // FileType.any: Android cannot filter on extensions such as .gpx or .geojson
    // that have no registered MIME type. The extension is checked after picking.
    final picked=await FilePicker.platform.pickFiles(withData:true);
    if(picked==null||picked.files.isEmpty)return;
    final file=picked.files.single;
    try{
      final bytes=await readPickedFile(file);
      if(bytes==null)throw ImportFormatException(S.t('map.unreadable'));
      final result=parseMapFile(file.name,bytes);
      final created=_drawing.importShapes(result.shapes);
      _fitPoints([for(final f in created)...f.points]);
      final skipped=result.skipped>0?S.t('map.importSkipped',{'n':result.skipped}):'';
      messenger.showSnackBar(SnackBar(content:Text(S.t('map.importDone',{'n':created.length,'file':file.name,'skipped':skipped}))));
    }on ImportFormatException catch(e){
      messenger.showSnackBar(SnackBar(content:Text(e.message)));
    }catch(e){
      messenger.showSnackBar(SnackBar(content:Text(S.t('map.importFailed',{'error':e}))));
    }
  }

  void _fitPoints(List<LatLng> pts){
    if(pts.isEmpty)return;
    if(pts.length==1){_map.move(pts.first,15);return;}
    _map.fitCamera(CameraFit.coordinates(coordinates:pts,padding:const EdgeInsets.all(60),maxZoom:17));
  }

  /// Exports the event's drawn objects as GeoJSON: a local copy on the device,
  /// and an upload to the event's shared files so the PCO receives it.
  Future<void> _exportGeoJson() async {
    final messenger=ScaffoldMessenger.of(context);
    final stamp=DateTime.now().toIso8601String().substring(0,16).replaceAll(RegExp(r'[:T]'),'-');
    final name='sarcade-objets-${widget.eventId}-$stamp.geojson'.replaceAll(RegExp(r'[\\/:*?"<>|]'),'_');
    final bytes=utf8.encode(const JsonEncoder.withIndent('  ').convert(featureCollection(_drawing.features)));
    String? localPath;
    try{localPath=await saveFile(name,bytes,mimeType:'application/geo+json');}catch(_){localPath=null;}
    var shared=false;
    try{await widget.api.uploadFile(widget.eventId,widget.deviceId,name,'application/geo+json',bytes);shared=true;}catch(_){}
    if(!mounted)return;
    final count=_drawing.features.length;
    messenger.showSnackBar(SnackBar(
      duration:const Duration(seconds:6),
      content:Text(shared?S.t('map.exportShared',{'n':count}):localPath!=null?S.t('map.exportLocal',{'n':count}):S.t('map.exportFailed')),
      action:localPath==null||!canOpenSavedFiles?null:SnackBarAction(label:S.t('map.open'),onPressed:()=>openSavedFile(localPath!)),
    ));
  }

  /// PowerPoint-like keyboard shortcuts for keyboards and mice: Chromebook,
  /// Windows and Linux. Ignored while a text field has the focus, so typing
  /// in the search field never deletes or undoes a map object.
  Widget _withDrawingShortcuts(Widget child)=>Focus(
    autofocus:true,
    onKeyEvent:(node,event){
      if(event is! KeyDownEvent&&event is! KeyRepeatEvent)return KeyEventResult.ignored;
      final focused=FocusManager.instance.primaryFocus?.context;
      if(focused!=null&&(focused.widget is EditableText||focused.findAncestorWidgetOfExactType<EditableText>()!=null)){
        return KeyEventResult.ignored;
      }
      final keys=HardwareKeyboard.instance;
      final ctrl=keys.isControlPressed||keys.isMetaPressed;
      final key=event.logicalKey;
      bool run(VoidCallback action){action();return true;}
      final handled=switch(key){
        LogicalKeyboardKey.delete||LogicalKeyboardKey.backspace when _drawing.selected!=null=>run(_drawing.deleteSelected),
        LogicalKeyboardKey.keyZ when ctrl&&keys.isShiftPressed=>run(_drawing.redo),
        LogicalKeyboardKey.keyZ when ctrl=>run(_drawing.undo),
        LogicalKeyboardKey.keyY when ctrl=>run(_drawing.redo),
        LogicalKeyboardKey.keyD when ctrl&&_drawing.selected!=null=>run(()=>_drawing.duplicateSelected()),
        LogicalKeyboardKey.enter||LogicalKeyboardKey.numpadEnter when _drawing.canFinish=>run(()=>_drawing.finish()),
        LogicalKeyboardKey.escape when _drawing.isDrawing=>run(()=>_drawing.selectTool(null)),
        LogicalKeyboardKey.escape when _drawing.selected!=null=>run(()=>_drawing.select(null)),
        _=>false,
      };
      return handled?KeyEventResult.handled:KeyEventResult.ignored;
    },
    child:child,
  );

  @override void dispose(){_rtSub?.cancel();_tracking.removeListener(_onOperationsChanged);_ops.removeListener(_onOperationsChanged);_tracking.dispose();_ops.dispose();_routes.removeListener(_onRoutesChanged);_nav.removeListener(_onRoutesChanged);_routes.dispose();_nav.dispose();_measure.removeListener(_onRoutesChanged);_measure.dispose();_syncUiTimer?.cancel();_sync.dispose();_realtime.dispose();_drawing.dispose();widget.api.close();super.dispose();}

  @override Widget build(BuildContext context){
    final sorted=_positions.values.where((p)=>_showAprs||!p.isAprs).toList()..sort((a,b)=>a.deviceId.compareTo(b.deviceId));
    final markers=<Marker>[
      ...sorted.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:130,height:62,alignment:Alignment.topCenter,child:GestureDetector(onTap:()=>_select(p),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(p.isAprs?Icons.settings_input_antenna:Icons.person_pin_circle,size:p.isAprs?30:38,color:p.deviceId==widget.deviceId?Colors.orange:(_selectedDevice==p.deviceId?Colors.deepPurple:(p.isAprs?Colors.purple.shade400:Colors.blue))),Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(5),boxShadow:const [BoxShadow(blurRadius:2)]),child:Text(p.label,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600)))])))),
      ..._pois.values.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:40,height:40,child:Tooltip(message:p.label??p.kind,child:const Icon(Icons.location_on,size:38,color:Colors.red)))),
      ..._references.values.where((r)=>(r.isHighPoint&&_showHighPoints)||(r.isRelay&&_showRelays)).map((r)=>Marker(
        point:LatLng(r.lat,r.lon),width:46,height:46,
        child:Tooltip(message:r.name,child:GestureDetector(onTap:()=>_selectReference(r),child:Icon(r.isHighPoint?Icons.terrain:Icons.cell_tower,size:34,color:r.isHighPoint?Colors.indigo:Colors.deepOrange))),
      )),
    ];
    final selected=_selectedDevice==null?null:_positions[_selectedDevice];
    final screenWidth=MediaQuery.sizeOf(context).width;
    final compact=screenWidth<_compactWidth;
    // On a phone a panel takes most of the width, leaving a strip of map visible.
    double panelWidth(double w)=>compact?(screenWidth*0.85).clamp(0.0,w):w;
    void toggleOperators()=>setState((){_showPanel=!_showPanel;if(_showPanel)_showReferencePanel=false;});
    void toggleReferences()=>setState((){_showReferencePanel=!_showReferencePanel;if(_showReferencePanel){_showPanel=false;_showRoutesPanel=false;}});
    void toggleRoutes()=>setState((){_showRoutesPanel=!_showRoutesPanel;if(_showRoutesPanel){_showPanel=false;_showReferencePanel=false;}else{_drawingRouteId=null;}});
    void openFiles()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FilesPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId)));
    void openLogbook()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LogbookPage(api:widget.api,eventId:widget.eventId)));
    final syncButton=IconButton(tooltip:S.t('map.sync'),onPressed:() async {await _sync.syncNow();if(mounted)setState((){});},icon:const Icon(Icons.sync));
    final messagesButton=IconButton(tooltip:S.t('map.messages'),onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId,sync:_sync,store:widget.store))),icon:Badge(label:Text('${widget.store.pendingCount()}'),child:const Icon(Icons.message)));
    return Scaffold(
      appBar:compact
        ? AppBar(
            titleSpacing:12,
            title:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[const Text('SARCADE'),Text('$_status · ${S.t('status.pending',{'n':widget.store.pendingCount()})}',style:Theme.of(context).textTheme.labelSmall,overflow:TextOverflow.ellipsis)]),
            actions:[
              syncButton,
              messagesButton,
              PopupMenuButton<String>(
                tooltip:S.t('map.menu'),
                onSelected:(v){switch(v){case 'fit':_fitOperators();case 'operators':toggleOperators();case 'references':toggleReferences();case 'routes':toggleRoutes();case 'weather':_openWeather();case 'goto':_gotoCoordinates();case 'basemap':_chooseBasemap();case 'files':openFiles();case 'logbook':openLogbook();case 'settings':widget.onSettings?.call();}},
                itemBuilder:(_)=>[
                  PopupMenuItem(value:'fit',child:ListTile(leading:const Icon(Icons.center_focus_strong),title:Text(S.t('map.fit')))),
                  PopupMenuItem(value:'operators',child:ListTile(leading:const Icon(Icons.groups),title:Text(S.t('map.operators')))),
                  PopupMenuItem(value:'goto',child:ListTile(leading:const Icon(Icons.pin_drop_outlined),title:Text(S.t('measure.goto')))),
                  PopupMenuItem(value:'weather',child:ListTile(leading:const Icon(Icons.cloud_outlined),title:Text(S.t('weather.menu')))),
                  PopupMenuItem(value:'basemap',child:ListTile(leading:const Icon(Icons.layers_outlined),title:Text(S.t('basemap.menu')))),
                  PopupMenuItem(value:'routes',child:ListTile(leading:const Icon(Icons.route),title:Text(S.t('routes.menu')))),
                  PopupMenuItem(value:'references',child:ListTile(leading:const Icon(Icons.cell_tower),title:Text(S.t('map.references')))),
                  PopupMenuItem(value:'files',child:ListTile(leading:const Icon(Icons.folder_copy_outlined),title:Text(S.t('map.files')))),
                  PopupMenuItem(value:'logbook',child:ListTile(leading:const Icon(Icons.receipt_long),title:Text(S.t('map.logbook')))),
                  if(widget.onSettings!=null)PopupMenuItem(value:'settings',child:ListTile(leading:const Icon(Icons.settings),title:Text(S.t('map.settings')))),
                ],
              ),
            ])
        : AppBar(title:const Text('SARCADE'),actions:[syncButton,IconButton(tooltip:S.t('map.fit'),onPressed:_fitOperators,icon:const Icon(Icons.center_focus_strong)),IconButton(tooltip:S.t('map.operators'),onPressed:toggleOperators,icon:const Icon(Icons.groups)),IconButton(tooltip:S.t('map.references'),onPressed:toggleReferences,icon:const Icon(Icons.cell_tower)),IconButton(tooltip:S.t('routes.menu'),onPressed:toggleRoutes,icon:const Icon(Icons.route)),IconButton(tooltip:S.t('weather.menu'),onPressed:()=>_openWeather(),icon:const Icon(Icons.cloud_outlined)),IconButton(tooltip:S.t('measure.goto'),onPressed:_gotoCoordinates,icon:const Icon(Icons.pin_drop_outlined)),IconButton(tooltip:S.t('basemap.menu'),onPressed:_chooseBasemap,icon:const Icon(Icons.layers_outlined)),messagesButton,IconButton(tooltip:S.t('map.files'),onPressed:openFiles,icon:const Icon(Icons.folder_copy_outlined)),IconButton(tooltip:S.t('map.logbook'),onPressed:openLogbook,icon:const Icon(Icons.receipt_long)),if(widget.onSettings!=null)IconButton(tooltip:S.t('map.settings'),onPressed:widget.onSettings,icon:const Icon(Icons.settings)),Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Center(child:Text('$_status · ${S.t('status.pending',{'n':widget.store.pendingCount()})}')))]),
      body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        OperationsBanners(settings:_ops.settings,update:_ops.update,
          alert:syncAlert(widget.store.pending(),DateTime.now(),_ops.settings.syncAlertMinutes),
          heldPhotos:_sync.lowBandwidth?widget.store.pendingUploads().length:0,
          onSyncNow:() async {await _sync.syncNow();if(mounted)setState((){});},
          onUpdate:()=>downloadUpdate(context,widget.api,_ops.update)),
        Expanded(child:_withDrawingShortcuts(Row(children:[
        if(_showRoutesPanel)SizedBox(width:panelWidth(360),child:Material(elevation:3,child:RoutesPanel(
          controller:_routes,api:widget.api,actorId:widget.deviceId,selectedRouteId:_selectedRouteId,drawingRouteId:_drawingRouteId,
          groups:widget.store.groups(widget.eventId).map(CommGroup.fromJson).toList(),
          onSelect:(id)=>setState((){_selectedRouteId=id;if(id==null)_drawingRouteId=null;}),
          onDraw:(id)=>setState((){_drawingRouteId=id;_drawingClosure=false;}),
          onDrawClosure:()=>setState((){_drawingClosure=true;_drawingRouteId=null;_closureDraft.clear();}),
          onNavigate:_navigateTo,
          onFocus:_fitPoints,
        ))),
        if(_showReferencePanel)SizedBox(width:panelWidth(355),child:Material(elevation:3,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.fromLTRB(14,8,6,0),child:Row(children:[Expanded(child:Text(S.t('refs.title',{'n':_filteredReferences().length}),style:Theme.of(context).textTheme.titleMedium)),IconButton(tooltip:S.t('refs.refresh'),onPressed:()=>_refreshReferences(),icon:const Icon(Icons.refresh))])),
          Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:TextField(decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:S.t('refs.search'),isDense:true,border:const OutlineInputBorder()),onChanged:(v)=>setState(()=>_referenceQuery=v))),
          Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Wrap(spacing:8,children:[
            FilterChip(label:Text(S.t('refs.highPoints')),selected:_showHighPoints,onSelected:(v)=>setState(()=>_showHighPoints=v)),
            FilterChip(label:Text(S.t('refs.relays')),selected:_showRelays,onSelected:(v)=>setState(()=>_showRelays=v)),
          ])),
          Expanded(child:ListView.builder(itemCount:_filteredReferences().length,itemBuilder:(context,index){final r=_filteredReferences()[index];return ListTile(selected:_selectedReference?.id==r.id,leading:Icon(r.isHighPoint?Icons.terrain:Icons.cell_tower,color:r.isHighPoint?Colors.indigo:Colors.deepOrange),title:Text(r.name),subtitle:Text(r.subtitle),onTap:()=>_selectReference(r));})),
          if(_selectedReference!=null)Builder(builder:(context){final r=_selectedReference!;return Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(border:Border(top:BorderSide(color:Theme.of(context).dividerColor))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(r.name,style:const TextStyle(fontWeight:FontWeight.bold)),
            if(r.callsign?.isNotEmpty==true)Text(S.t('refs.callsign',{'v':r.callsign})),
            if(r.isHighPoint&&r.altM!=null)Text(S.t('refs.altitude',{'v':r.altM!.toStringAsFixed(0)})),
            if(r.subtype?.isNotEmpty==true)Text(S.t('refs.type',{'v':r.subtype})),
            if(r.mode?.isNotEmpty==true)Text(S.t('refs.mode',{'v':r.mode})),
            if(r.isRelay)Text(S.t('refs.input',{'v':_frequency(r.rxMhz)})),
            if(r.isRelay)Text(S.t('refs.output',{'v':_frequency(r.txMhz)})),
            if(r.ctcssRx?.isNotEmpty==true)Text(S.t('refs.ctcssIn',{'v':r.ctcssRx})),
            if(r.ctcssTx?.isNotEmpty==true)Text(S.t('refs.ctcssOut',{'v':r.ctcssTx})),
            if(r.access?.isNotEmpty==true)Text(S.t('refs.access',{'v':r.access})),
            if(r.clearance?.isNotEmpty==true)Text(S.t('refs.clearance',{'v':r.clearance})),
            if(r.verifiedAt?.isNotEmpty==true)Text(S.t('refs.verified',{'v':r.verifiedAt})),
          ]));}),
        ]))),
        if(_showPanel)SizedBox(width:panelWidth(285),child:Material(elevation:3,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.fromLTRB(14,14,14,4),child:Text(S.t('operators.title',{'n':sorted.length}),style:Theme.of(context).textTheme.titleMedium)),
          if(_positions.values.any((p)=>p.isAprs))Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Align(alignment:Alignment.centerLeft,child:Tooltip(message:S.t('operators.aprsHint'),
            child:FilterChip(avatar:const Icon(Icons.settings_input_antenna,size:18),label:Text(S.t('operators.aprs')),selected:_showAprs,onSelected:(v)=>setState(()=>_showAprs=v))))),
          Expanded(child:ListView(children:sorted.map((p)=>ListTile(selected:_selectedDevice==p.deviceId,leading:Icon(Icons.circle,size:13,color:DateTime.now().toUtc().difference(p.time.toUtc()).inMinutes<5?Colors.green:Colors.grey),title:Text(p.label),subtitle:Text([if(p.isAprs)S.t('operators.aprsVia',{'via':p.aprsVia??'APRS'}),S.t('operators.lastPosition',{'age':_age(p.time)})].join(' · ')),onTap:()=>_select(p))).toList())),
          if(selected!=null)Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(border:Border(top:BorderSide(color:Theme.of(context).dividerColor))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(selected.deviceId,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('Lat : ${selected.lat.toStringAsFixed(6)}'),Text('Lon : ${selected.lon.toStringAsFixed(6)}'),Text(S.t('operators.accuracy',{'m':selected.accuracyM?.toStringAsFixed(1)??'-'})),Text(S.t('operators.time',{'time':selected.time.toLocal()})),Text(_traceLoading?S.t('operators.traceLoading'):S.t('operators.trace',{'n':_trace.length}))]))
        ]))),
        Expanded(child:Stack(key:_mapKey,children:[FlutterMap(mapController:_map,options:MapOptions(
          initialCenter:const LatLng(48.8566,2.3522),initialZoom:11,maxZoom:20,onTap:_onMapTap,
          onLongPress:(_,point)=>_onLongPress(point),
          onSecondaryTap:(_,point)=>_onLongPress(point),
          // Rotation off: drawn arrows and handles assume north up.
          // Drag off while editing so handle and freehand gestures reach the shapes.
          interactionOptions:InteractionOptions(flags:InteractiveFlag.all&~InteractiveFlag.rotate&(_drawing.locksMapDrag?~InteractiveFlag.drag:~0)),
        ),children:[
          TileLayer(key:ValueKey(_tileUrl),urlTemplate:_tileUrl,userAgentPackageName:'org.sarcade.app',maxZoom:_basemap.maxZoom.toDouble()),
          if(_trace.length>1)PolylineLayer(polylines:_traceSegments().map((segment)=>Polyline(points:segment.map((p)=>LatLng(p.lat,p.lon)).toList(),strokeWidth:4,color:Colors.deepPurple)).toList()),
          ...buildDrawingLayers(_drawing),
          ...buildRouteLayers(_routes,selectedRouteId:_selectedRouteId,itinerary:_nav.itinerary?.geometry??const [],draftClosure:_closureDraft,
            onWaypointTap:(w)=>setState((){_showRoutesPanel=true;_showPanel=false;_showReferencePanel=false;_selectedRouteId=w.routeId;})),
          ...buildMeasureLayers(_measure,_coordFormat),
          MarkerLayer(markers:markers),
          buildHandleLayer(_drawing,_globalToLatLng),
          RichAttributionWidget(attributions:[TextSourceAttribution(_basemap.attribution.isEmpty?widget.tileAttribution:_basemap.attribution)]),
        ]),
        if(_drawing.tool==FeatureKind.freehand)Positioned.fill(child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onPanStart:_onFreehandStart,onPanUpdate:_onFreehandUpdate,onPanEnd:_onFreehandEnd,
          child:CustomPaint(painter:_StrokePainter(_stroke,Color(_drawing.color),_drawing.strokeWidth)),
        )),
        Positioned(top:8,left:8,right:8,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(_drawingTools)DrawingToolbar(controller:_drawing,onExport:_exportGeoJson,onImport:_importFile,onClose:(){_drawing.selectTool(null);setState(()=>_drawingTools=false);})
          else FloatingActionButton.small(heroTag:'drawing-tools',tooltip:S.t('draw.open'),onPressed:()=>setState(()=>_drawingTools=true),child:const Icon(Icons.draw_outlined)),
          if(_drawing.isDrawing)Padding(padding:const EdgeInsets.only(top:8),child:DraftBar(controller:_drawing)),
          if(_drawing.selected!=null)Padding(padding:const EdgeInsets.only(top:8),child:SelectionBar(controller:_drawing,onEditLabel:_editSelectedLabel)),
          if(_drawingClosure)Padding(padding:const EdgeInsets.only(top:8),child:Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.block,color:Colors.red),const SizedBox(width:8),
            Flexible(child:Text(S.t('closures.drawHelp'))),
            TextButton(onPressed:()=>setState((){_drawingClosure=false;_closureDraft.clear();}),child:Text(S.t('closures.cancel'))),
            FilledButton(onPressed:_finishClosure,child:Text(S.t('closures.finish'))),
          ])))),
        ])),
        Positioned(left:0,right:0,bottom:72,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Column(mainAxisSize:MainAxisSize.min,children:[
          MeasureCard(m:_measure,format:_coordFormat,onSavePoi:_savePoi,onSendMessage:_sendMeasure,
            onFit:(){final o=_measure.origin,t=_measure.target;if(t!=null)_fitPoints([?o?.point,t]);},
            onOpenElsewhere:(){final t=_measure.target;if(t!=null)openInOtherApp(context,t,_measure.targetLabel);},
            onChooseOrigin:_chooseOrigin,
            onFormat:(f) async {await widget.store.setPreference('coord_format',f.name);if(mounted)setState((){});}),
          NavigationCard(nav:_nav),
        ])))),
      ]))
      ]))),
      ]),
      floatingActionButton:FloatingActionButton.extended(onPressed:_openTracking,
        icon:Icon(_tracking.enabled?Icons.my_location:Icons.location_searching),
        label:Text(_tracking.enabled?S.t('tracking.on',{'interval':intervalLabel(_tracking.intervalS,S.t)}):S.t('tracking.start'))),
    );
  }
}

/// Live preview of the freehand stroke, in screen space, while the finger moves.
class _StrokePainter extends CustomPainter {
  final List<Offset> points; final Color color; final double width;
  _StrokePainter(this.points,this.color,this.width);
  @override void paint(Canvas canvas,Size size){
    if(points.length<2)return;
    final path=Path()..moveTo(points.first.dx,points.first.dy);
    for(final p in points.skip(1)){path.lineTo(p.dx,p.dy);}
    canvas.drawPath(path,Paint()..color=color..strokeWidth=width..style=PaintingStyle.stroke..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round);
  }
  @override bool shouldRepaint(_StrokePainter old)=>true;
}
