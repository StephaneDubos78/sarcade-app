import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:uuid/uuid.dart';

import '../../models/comm_group.dart';
import '../../models/message_reception.dart';
import '../../models/message_unread.dart';
import '../../models/poi.dart';
import '../../models/message.dart';
import '../../models/position.dart';
import '../../models/reference_site.dart';
import '../messages/messages_page.dart';
import '../logbook/logbook_page.dart';
import '../search/map_search.dart';
import '../search/map_search_bar.dart';
import '../../ui/map_view.dart';
import '../../ui/theme.dart';
import 'stations.dart';
import '../bearings/bearing_controller.dart';
import '../bearings/bearing_layers.dart';
import '../bearings/bearing_models.dart';
import 'drawing/geometry.dart' as geo;
import '../files/files_page.dart';
import 'drawing/drawing_controller.dart';
import 'reference_cluster_layer.dart';
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
import '../../offline/unsent_page.dart';
import '../../access/access_login_page.dart';
import '../../access/access_manager.dart';
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
  StreamSubscription? _rtSub; Timer? _syncUiTimer; bool _started=false, _starting=false; bool _showPanel=true; bool _showReferencePanel=false; bool _showHighPoints=true; bool _showRelays=true; String _referenceQuery=''; String? _selectedDevice; ReferenceSite? _selectedReference; List<SarcadePosition> _trace=[]; bool _traceLoading=false; late final OfflineSyncService _sync; bool _layoutInitialized=false;
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

  @override void initState(){super.initState();_notifications.initialize();unawaited(requestPersistentStorage());_sync=OfflineSyncService(api:widget.api,store:widget.store,eventId:widget.eventId,onRemoteChange:_onRemoteChange);_initDrawing();_initBearings();_loadLocal();_initRoutes();_initMeasure();_sync.start();_initOperations();_loadBasemaps();_syncUiTimer=Timer.periodic(const Duration(seconds:2),(_){if(mounted)setState((){});});AccessManager.instance.addListener(_onAccessChanged);_start();}
  bool _validPosition(SarcadePosition p){
    final t=p.time.toUtc(), now=DateTime.now().toUtc();
    return t.isAfter(DateTime.utc(2020)) && t.isBefore(now.add(const Duration(days:1)));
  }
  void _loadLocal(){for(final j in widget.store.positions()){final p=SarcadePosition.fromJson(j);if(p.eventId==widget.eventId&&_validPosition(p))_positions[p.deviceId]=p;}for(final j in widget.store.pois()){final p=SarcadePoi.fromJson(j);if(p.eventId==widget.eventId)_pois[p.id]=p;}for(final j in widget.store.references()){final p=ReferenceSite.fromJson(j);if(p.status=='active')_references[p.id]=p;}}
  Future<void> _start() async {
    if(_starting)return; _starting=true;
    try {
      final data=await Future.wait([widget.api.latestPositions(widget.eventId),widget.api.pois(widget.eventId)]);
      _mergePositions(data[0] as List<SarcadePosition>);
      for(final p in data[1] as List<SarcadePoi>){_pois[p.id]=p;}
      // Safety net: positions only come by the realtime channel; read the
      // latest ones again every minute in case some were missed.
      _positionsTimer?.cancel();
      _positionsTimer=Timer.periodic(const Duration(seconds:60),(_)=>unawaited(_reloadPositions()));
      try{await _refreshReferences(silent:true);}catch(_){}
      _realtime.connect(widget.api.websocketUri(widget.eventId),headers:widget.api.realtimeHeaders);
      await _rtSub?.cancel();
      _rtSub=_realtime.events.listen(_onRealtime);
      if(mounted){setState(()=>_started=true);if(_savedView==null)WidgetsBinding.instance.addPostFrameCallback((_)=>_fitOperators());}
    } catch(e){if(mounted)setState((){});} finally {_starting=false;}
  }
  Timer? _positionsTimer;
  /// Keeps the newest position of each device (a late answer never moves a
  /// marker back).
  void _mergePositions(Iterable<SarcadePosition> list){
    for(final p in list){
      if(!_validPosition(p))continue;
      final known=_positions[p.deviceId];
      if(known!=null&&!p.time.isAfter(known.time))continue;
      _positions[p.deviceId]=p; widget.store.cachePosition(p.toJson());
    }
  }
  Future<void> _reloadPositions() async {
    try{
      final list=await widget.api.latestPositions(widget.eventId);
      if(!mounted)return;
      setState(()=>_mergePositions(list));
    }catch(_){/* offline: the next reload or the realtime channel will bring them */}
  }

  /// Status at the top of the screen, from the last exchange with the server
  /// and the real-time channel, refreshed every 2 s.
  String get _status{
    // Cloudflare Access answered instead of SARCADE: the server is reachable,
    // the operator must sign in (not « Hors connexion »).
    if(AccessManager.instance.requiredFor(widget.api.baseUrl))return S.t('status.accessRequired');
    if(!_sync.lastSyncOk)return S.t(_started||_sync.lastServerContact!=null?'status.offline':'status.connecting');
    if(_sync.eventUnknown)return S.t('status.eventUnknown');
    // Started without network: load the map data and open real time now.
    if(!_started){_start();return S.t('status.connecting');}
    final unsent=_sync.unsent;
    // Server reachable but items set aside: « Connecté · n non envoyés ».
    if(unsent>0)return S.t('status.unsent',{'n':unsent});
    if(!_realtime.connected){_realtime.reconnectNow();return S.t('status.realtimeUnavailable');}
    return S.t('status.connected');
  }
  /// Status line: connection state, then the items on their way.
  String get _statusLine{
    final n=_sync.inFlight;
    return n>0?'$_status · ${S.t('status.inFlight',{'n':n})}':_status;
  }
  Color? get _statusColor=>AccessManager.instance.requiredFor(widget.api.baseUrl)||(_sync.lastSyncOk&&(_sync.unsent>0||_sync.eventUnknown))?Colors.deepOrange:null;

  /// « Se connecter »: after the sign-in everything that waited leaves.
  Future<void> _signIn() async {
    if(!await signInToServer(context,widget.api.baseUrl))return;
    _realtime.disconnect();
    if(mounted)setState(()=>_started=false);
    await _sync.syncNow();
    unawaited(_ops.beat());
    unawaited(_start());
  }

  /// Session ending within 24 h: date shown in the reminder banner.
  DateTime? get _accessRenewBy{
    final s=AccessManager.instance.sessionFor(widget.api.baseUrl);
    return s!=null&&s.renewSoon(DateTime.now().toUtc())?s.expiresAt:null;
  }
  void _onAccessChanged(){if(mounted)setState((){});}

  void _toggleDrawingTools(){
    if(_drawingTools)_drawing.selectTool(null);
    setState(()=>_drawingTools=!_drawingTools);
  }
  void _openUnsent()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>UnsentPage(sync:_sync,actorId:widget.deviceId))).then((_){if(mounted)setState((){});});
  void _onRealtime(RealtimeEvent e){
    if(e.type==RealtimeService.reconnectedType){unawaited(_reloadPositions());return;}
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

  /// Messages being handled: realtime and synchronisation may deliver the
  /// same one at the same moment.
  final _receiving=<String>{};
  Future<void> _receiveMessage(Map<String,dynamic> data) async {
    final m=SarcadeMessage.fromJson(data);
    if(!_receiving.add(m.id))return;
    try{await _handleMessage(m,data);}finally{_receiving.remove(m.id);}
  }
  Future<void> _handleMessage(SarcadeMessage m,Map<String,dynamic> data) async {
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
      // Realtime and synchronisation may both bring the message: only the
      // first arrival notifies; an old message caught up later stays silent.
      if(shouldNotifyMessage(alreadyReceived:existing,createdAt:m.createdAt,now:DateTime.now().toUtc())){
        await _notifications.message(title:'SARCADE · ${S.t('priority.${m.priority}')} · ${m.senderId}',body:m.body,priority:m.priority);
      }
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
      ListTile(leading:const Icon(Icons.track_changes),title:Text(S.t('bearings.fromHere')),onTap:()=>Navigator.pop(c,'bearing')),
    ])));
    if(choice=='bearing'){await _bearings.startTaking(from:point);return;}
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

  /// Web client: « Activer les notifications » until the operator answers
  /// (or chooses « Plus tard » for this session).
  bool _notificationsDismissed=false;
  bool get _notificationsBanner=>!_notificationsDismissed&&_notifications.needsUserAction;
  Future<void> _enableNotifications() async {
    final ok=await _notifications.requestFromUser();
    if(!mounted)return;
    setState((){});
    if(!ok)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('notifications.refused'))));
  }

  /// Unread messages: count on the Messages button, red when one is urgent.
  /// The first time on this device every existing message counts as seen.
  Widget _messagesIcon(){
    final all=widget.store.messages().map(SarcadeMessage.fromJson).where((m)=>m.eventId==widget.eventId).toList();
    final seen=widget.store.seenMessages(widget.eventId);
    if(seen==null){unawaited(widget.store.markMessagesSeen(widget.eventId,all.map((m)=>m.id)));return const Icon(Icons.message);}
    final groups={for(final j in widget.store.groups(widget.eventId)) j['id'] as String:CommGroup.fromJson(j)};
    final unread=unreadMessages(messages:all,seen:seen,deviceId:widget.deviceId,groups:groups);
    return Badge(isLabelVisible:unread.isNotEmpty,label:Text('${unread.length}'),
      backgroundColor:anyUrgent(unread)?Colors.red:Colors.blueGrey,child:const Icon(Icons.message));
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
  Future<void> _select(SarcadePosition p,{bool move=true}) async {
    setState((){_selectedDevice=p.deviceId;_traceLoading=true;_trace=[];_history=[];_scrub=null;});
    if(move)_map.move(LatLng(p.lat,p.lon),_map.camera.zoom<15?15:_map.camera.zoom);
    try{
      final h=await widget.api.positionHistory(widget.eventId,p.deviceId,limit:2000);
      if(mounted&&_selectedDevice==p.deviceId)setState((){_history=h.where(_validPosition).toList();_trace=traceWithin(_history,DateTime.now().toUtc(),_traceHours);});
    }finally{if(mounted)setState(()=>_traceLoading=false);}
  }
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
      if(Bearing.isBearing(j))continue; // bearings have their own controller
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

  /// Changes pulled by the automatic synchronisation (every 20 s): shown on
  /// the map even when the real-time channel missed them (test of 23 Oct
  /// 2026: the phone's positions reached the server but not the PC map).
  void _onRemoteChange(String objectType,Map<String,dynamic> payload){
    // Messages brought by the synchronisation (realtime closed, app back in
    // the foreground) get the same acknowledgement and notification.
    if(objectType=='message'&&payload['event_id']==widget.eventId)unawaited(_receiveMessage(payload));
    if(objectType=='map_feature')_applyRemoteFeature(payload);
    if(routeObjectKinds.contains(objectType))_routes.applyRemote(objectType,payload);
    if(objectType=='position'){
      final p=SarcadePosition.fromJson(payload);
      final current=_positions[p.deviceId];
      if(p.eventId==widget.eventId&&_validPosition(p)&&(current==null||p.time.isAfter(current.time))&&mounted){
        setState((){_positions[p.deviceId]=p;if(_selectedDevice==p.deviceId)_trace.add(p);});
      }
    }
    if(objectType=='poi'){
      final p=SarcadePoi.fromJson(payload);
      if(p.eventId==widget.eventId&&mounted)setState(()=>_pois[p.id]=p);
    }
  }

  /// Server state of a map object, from the change feed or realtime.
  /// A local change still waiting in the Outbox keeps priority until the
  /// server has ruled on it; the winning state then arrives through the feed.
  void _applyRemoteFeature(Map<String,dynamic> p,{bool persist=false}){
    final id=p['id'];
    if(id is! String||p['event_id']!=widget.eventId||_sync.isPending(id))return;
    if(p['deleted']==true)_bearings.remove(id);
    if(p['deleted']!=true&&Bearing.isBearing(p)){
      try{_bearings.applyRemote(Bearing.fromJson(p));if(persist)widget.store.saveMapFeature(p);}catch(_){}
      return;
    }
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
    if(_searchPin!=null){setState(()=>_searchPin=null);return;}
    final cam=_map.camera;
    final hit=hitTest(_drawing.features,tap.relative??cam.latLngToScreenOffset(point),cam.latLngToScreenOffset,radiusPx:_circleRadiusPx);
    if(hit==null&&_closeOpenItems())return;
    _drawing.select(hit?.id);
  }

  /// A tap on the map closes what is open, as in Google Maps (request of
  /// 26 Oct 2026): selected object, operator trace, reference sheet,
  /// measure; on a phone also the side panels (on a computer they stay,
  /// one works in them while looking at the map). True if something closed.
  bool _closeOpenItems(){
    final compact=MediaQuery.sizeOf(context).width<_compactWidth;
    var closed=false;
    if(_drawing.selected!=null){_drawing.select(null);closed=true;}
    if(_measure.active){unawaited(_measure.clear());closed=true;}
    if(_selectedDevice!=null||_trace.isNotEmpty){_selectedDevice=null;_trace=[];closed=true;}
    if(_selectedReference!=null){_selectedReference=null;closed=true;}
    if(compact&&(_showPanel||_showReferencePanel||_showRoutesPanel)){_showPanel=false;_showReferencePanel=false;_showRoutesPanel=false;_drawingRouteId=null;closed=true;}
    if(closed)setState((){});
    return closed;
  }

  /// « Ma position » (request of 26 Oct 2026): first press centres the map
  /// on the device, a second press while centred follows it until the map
  /// is moved by hand.
  LatLng? _me; bool _followMe=false; StreamSubscription? _meSub; StreamSubscription? _mapEvents;
  Future<void> _myPosition() async {
    if(_me!=null&&_centredOnMe()){
      setState(()=>_followMe=!_followMe);
      if(_followMe){_startFollowingMe();}else{await _meSub?.cancel();_meSub=null;}
      return;
    }
    if(!await _location.ensurePermission()){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('map.noPosition'))));
      return;
    }
    final p=await _location.current();
    if(p==null||!mounted){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('map.noPosition'))));return;}
    setState(()=>_me=LatLng(p.latitude,p.longitude));
    _map.move(_me!,_map.camera.zoom<15?16:_map.camera.zoom);
    _watchMapMoves();
  }
  bool _centredOnMe(){final me=_me;if(me==null)return false;final c=_map.camera.center;return (c.latitude-me.latitude).abs()<1e-4&&(c.longitude-me.longitude).abs()<1e-4;}
  void _startFollowingMe(){
    _meSub?.cancel();
    _meSub=_location.positions().listen((p){
      if(!mounted)return;
      setState(()=>_me=LatLng(p.latitude,p.longitude));
      if(_followMe)_map.move(_me!,_map.camera.zoom);
    },onError:(_){});
  }
  /// Moving the map by hand stops the following.
  void _watchMapMoves(){
    _mapEvents??=_map.mapEventStream.listen((e){
      if(_followMe&&e.source!=MapEventSource.mapController&&e.source!=MapEventSource.nonRotatedSizeChange&&e is MapEventMove){
        setState(()=>_followMe=false); _meSub?.cancel(); _meSub=null;
      }
      if(e is MapEventRotate||e is MapEventRotateEnd)setState((){});
    });
  }

  /// Floating buttons on the right of the map: map type, my position, and
  /// the compass when the map is turned (tap: north up).
  Widget _mapButtons(){
    // The controller is attached once the map is built (first frame).
    double rotation=0; try{rotation=_map.camera.rotation;}catch(_){}
    final rotated=rotation%360!=0;
    final scheme=Theme.of(context).colorScheme;
    return Column(mainAxisSize:MainAxisSize.min,children:[
      FloatingActionButton.small(heroTag:'map-layers',tooltip:S.t('basemap.menu'),onPressed:_chooseBasemap,child:const Icon(Icons.layers_outlined)),
      const SizedBox(height:8),
      if(rotated)...[
        FloatingActionButton.small(heroTag:'map-north',tooltip:S.t('map.north'),onPressed:(){_map.rotate(0);setState((){});},
          child:Transform.rotate(angle:-rotation*3.141592653589793/180,child:const Icon(Icons.explore_outlined))),
        const SizedBox(height:8),
      ],
      FloatingActionButton.small(heroTag:'map-me',tooltip:S.t(_followMe?'map.followMeOn':'map.myPosition'),onPressed:_myPosition,
        backgroundColor:_followMe?scheme.primary:null,foregroundColor:_followMe?scheme.onPrimary:null,
        child:Icon(_followMe?Icons.navigation:Icons.my_location)),
    ]);
  }

  /// Map search (request of 26 Oct 2026): what the device knows, then the
  /// addresses from the server. The chosen result gets a red pin; a tap on
  /// it opens the point menu (measure, navigate, open in, weather).
  LatLng? _searchPin;
  Iterable<Searchable> _searchables()=>[
    for(final p in _positions.values)Searchable(SearchKind.operator,p.deviceId.replaceFirst('aprs:',''),p.deviceId.startsWith('aprs:')?'APRS':S.t('search.kind.operator'),LatLng(p.lat,p.lon)),
    for(final r in _references.values)Searchable(SearchKind.reference,r.name,[r.callsign,r.subtype,r.description].whereType<String>().join(' '),LatLng(r.lat,r.lon)),
    for(final p in _pois.values)Searchable(SearchKind.poi,p.label??p.kind,p.kind,LatLng(p.lat,p.lon)),
    for(final f in _drawing.features)if(f.label.trim().isNotEmpty&&f.points.isNotEmpty)Searchable(SearchKind.drawing,f.label,f.kind.name,f.points.first),
  ];
  Future<List<SearchResult>> _searchAddresses(String q,LatLng? near) async =>
    addressResults(await widget.api.geocode(q,lat:near?.latitude,lon:near?.longitude));
  LatLng? _mapCentre(){try{return _map.camera.center;}catch(_){return null;}}
  void _onSearchPick(SearchResult r){
    setState(()=>_searchPin=r.point);
    _map.move(r.point,r.kind==SearchKind.address||r.kind==SearchKind.coordinates?16:15);
  }

  // --- Map screen V2 (mock-up « Interface futuriste », 27 Oct 2026) ---

  /// Last view of this event, taken back at the next opening (Plex).
  late final ({double lat,double lon,double zoom})? _savedView=decodeView(widget.store.preference('view:${widget.eventId}'));
  Timer? _saveViewTimer; double _camZoom=11, _camLat=48.85;
  void _onCameraChanged(MapCamera camera){
    final zoomChanged=(camera.zoom-_camZoom).abs()>0.01||(camera.center.latitude-_camLat).abs()>0.05;
    _camZoom=camera.zoom; _camLat=camera.center.latitude;
    if(zoomChanged&&mounted)setState((){}); // scale bar
    _saveViewTimer?.cancel();
    _saveViewTimer=Timer(const Duration(seconds:2),()=>unawaited(widget.store.setPreference('view:${widget.eventId}',
      encodeView(camera.center.latitude,camera.center.longitude,camera.zoom))));
  }

  bool _darkTiles(BuildContext context)=>Theme.of(context).brightness==Brightness.dark&&!_basemap.id.contains('photo')&&!_basemap.id.contains('sat');

  void _toggleDayNight(){
    final next=Theme.of(context).brightness==Brightness.dark?ThemeMode.light:ThemeMode.dark;
    themeMode.value=next;
    unawaited(widget.store.setPreference('theme_mode',themeModeName(next)));
  }

  /// Filter chips under the search (Google Maps), kept per event.
  bool get _showOperators=>widget.store.preference('show_ops:${widget.eventId}')!='0';
  bool get _showDrawings=>widget.store.preference('show_draw:${widget.eventId}')!='0';
  Future<void> _setShown(String key,bool v) async {await widget.store.setPreference('$key:${widget.eventId}',v?null:'0');if(mounted)setState((){});}
  Widget _filterChips(){
    Widget chip(String label,bool on,ValueChanged<bool> set)=>Padding(padding:const EdgeInsets.only(right:6),
      child:FilterChip(label:Text(label),selected:on,onSelected:set,showCheckmark:false,visualDensity:VisualDensity.compact));
    return SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
      chip(S.t('chips.operators'),_showOperators,(v)=>_setShown('show_ops',v)),
      chip('APRS',_showAprs,(v)=>setState(()=>_showAprs=v)),
      chip(S.t('refs.highPoints'),_showHighPoints,(v)=>setState(()=>_showHighPoints=v)),
      chip(S.t('refs.relays'),_showRelays,(v)=>setState(()=>_showRelays=v)),
      chip(S.t('chips.drawings'),_showDrawings,(v)=>_setShown('show_draw',v)),
      chip(S.t('chips.bearings'),_showBearings,(v)=>_setShown('show_brg',v)),
      chip(S.t('chips.withoutInternet'),_withoutInternetOnly,(v)=>setState(()=>_withoutInternetOnly=v)),
    ]));
  }

  /// One pill for the links (Meshtastic, MeshCore): a dot per link, amber
  /// when one fails; a tap gives the detail and « Synchroniser ».
  Widget _linksPill(){
    final access=AccessManager.instance.requiredFor(widget.api.baseUrl);
    final links=<(String,bool?)>[(S.t('links.server'),_started?_sync.lastSyncOk:null),(S.t('links.realtime'),_started?_realtime.connected:null),
      if(access)(S.t('links.access'),false)];
    final n=linksCount([for(final l in links)l.$2]);
    final scheme=Theme.of(context).colorScheme;
    Widget dot(bool? ok)=>Container(width:9,height:9,margin:const EdgeInsets.symmetric(horizontal:2),
      decoration:BoxDecoration(color:ok==null?scheme.outline:ok?scheme.primary:scheme.tertiary,borderRadius:BorderRadius.circular(ok==false?2:5)));
    return Tooltip(message:'${S.t('links.title')} : ${n.ok}/${n.total} · $_statusLine',child:Material(color:Colors.transparent,child:InkWell(
      borderRadius:BorderRadius.circular(24),
      onTap:()=>showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final l in links)ListTile(leading:dot(l.$2),title:Text(l.$1),trailing:Text(l.$2==null?'—':l.$2!?S.t('links.ok'):S.t('links.down'))),
        ListTile(leading:const Icon(Icons.info_outline),title:Text(_statusLine)),
        ListTile(leading:const Icon(Icons.sync),title:Text(S.t('map.sync')),onTap:() async {Navigator.pop(c);await _sync.syncNow();if(mounted)setState((){});}),
        ListTile(leading:const Icon(Icons.outbox_outlined),title:Text('${S.t('unsent.title')} (${_sync.unsent})'),onTap:(){Navigator.pop(c);_openUnsent();}),
        if(access)ListTile(leading:const Icon(Icons.lock_outline),title:Text(S.t('access.signIn')),onTap:(){Navigator.pop(c);_signIn();}),
      ]))),
      child:Container(height:48,padding:const EdgeInsets.symmetric(horizontal:12),decoration:glass(context,radius:24),
        child:Row(mainAxisSize:MainAxisSize.min,children:[for(final l in links)dot(l.$2)])),
    )));
  }

  /// « Suivi actif · 30 s » always in sight (aprs.fi « Beacon »); a tap
  /// opens the tracking settings (formerly the button at the bottom).
  Widget _trackingBadge(){
    final scheme=Theme.of(context).colorScheme; final on=_tracking.enabled;
    return Material(color:Colors.transparent,child:InkWell(borderRadius:BorderRadius.circular(16),onTap:_openTracking,
      child:Container(height:32,padding:const EdgeInsets.symmetric(horizontal:12),
        decoration:BoxDecoration(color:on?scheme.primaryContainer:scheme.surface.withValues(alpha:0.92),borderRadius:BorderRadius.circular(16),
          border:Border.all(color:on?scheme.primary.withValues(alpha:0.6):scheme.outline)),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(on?Icons.my_location:Icons.location_disabled_outlined,size:16,color:on?scheme.primary:scheme.onSurfaceVariant),const SizedBox(width:6),
          Text(on?S.t('tracking.on',{'interval':intervalLabel(_tracking.intervalS,S.t)}):S.t('tracking.start'),
            style:TextStyle(fontSize:12,color:on?scheme.onPrimaryContainer:scheme.onSurface)),
        ]))));
  }

  /// Scale bar (OsmAnd), from the current zoom and latitude.
  Widget _scaleBar(){
    final b=scaleBar(_camZoom,_camLat);
    final c=Theme.of(context).colorScheme.onSurface;
    final shadow=[Shadow(blurRadius:3,color:Theme.of(context).colorScheme.surface)];
    return Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(b.label,style:TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:c,shadows:shadow)),
      Container(width:b.px,height:6,decoration:BoxDecoration(border:Border(left:BorderSide(color:c,width:2),right:BorderSide(color:c,width:2),bottom:BorderSide(color:c,width:2)))),
    ]);
  }

  // --- Stations V2: freshness, source, APRS symbols, favourites, trace, proximity ---
  bool _withoutInternetOnly=false, _showNearby=false;
  List<SarcadePosition> _history=[]; int _traceHours=1; SarcadePosition? _scrub;
  int get _ageingMin=>(_ops.settings.raw['position_ageing_min'] as num?)?.toInt()??2;
  int get _staleMin=>(_ops.settings.raw['position_stale_min'] as num?)?.toInt()??10;
  Set<String> get _favourites=>parseFavourites(widget.store.preference('favourites'));
  Future<void> _toggleFavourite(String id) async {
    final f=_favourites; if(!f.remove(id))f.add(id);
    await widget.store.setPreference('favourites',encodeFavourites(f));
    if(mounted)setState((){});
  }
  Future<void> _setTraceHours(int h) async {
    setState((){_traceHours=h;_scrub=null;_trace=traceWithin(_history,DateTime.now().toUtc(),h);});
  }

  Color _stationColor(SarcadePosition p){
    final s=Theme.of(context).colorScheme;
    if(p.deviceId==widget.deviceId)return s.tertiary;
    return p.isAprs?s.secondary:s.primary;
  }

  Widget _stationIcon(SarcadePosition p,{double size=34}){
    final s=Theme.of(context).colorScheme; final now=DateTime.now().toUtc();
    final f=freshness(p.time.toUtc(),now,ageingMin:_ageingMin,staleMin:_staleMin);
    final color=f==Freshness.stale?s.outline:_stationColor(p);
    final sym=p.isAprs?aprsSymbol(p.aprsSymbol):null;
    final initials=p.label.replaceAll(RegExp(r'[^A-Za-z0-9]'),'');
    return Stack(clipBehavior:Clip.none,alignment:Alignment.center,children:[
      Container(width:size,height:size,alignment:Alignment.center,
        decoration:BoxDecoration(color:s.surface,shape:sym?.overlay!=null?BoxShape.rectangle:BoxShape.circle,borderRadius:sym?.overlay!=null?BorderRadius.circular(8):null,
          border:Border.all(color:color,width:f==Freshness.stale?1.5:2.5)),
        child:sym==null?Text(initials.length>3?initials.substring(initials.length-3):initials,style:TextStyle(fontSize:size*0.3,fontWeight:FontWeight.w800,color:color))
          :sym.overlay!=null?Text(sym.overlay!,style:TextStyle(fontSize:size*0.45,fontWeight:FontWeight.w800,color:color))
          :Icon(sym.icon,size:size*0.58,color:color)),
      // Heading of a moving station (aprs.fi).
      if(p.headingDeg!=null&&(p.speedMps??0)>0.5)Positioned.fill(child:Transform.rotate(angle:p.headingDeg!*3.141592653589793/180,
        child:Align(alignment:Alignment.topCenter,child:Transform.translate(offset:const Offset(0,-9),child:Icon(Icons.navigation,size:14,color:color))))),
    ]);
  }

  /// Station markers, grouped with a number when they overlap (Tesla).
  List<Marker> _stationMarkers(List<SarcadePosition> list){
    final now=DateTime.now().toUtc(); final s=Theme.of(context).colorScheme;
    MapCamera? cam; try{cam=_map.camera;}catch(_){}
    final groups=cam==null||cam.zoom>=15?[for(final p in list)[p]]:clusterOnScreen(list,(p)=>cam!.latLngToScreenOffset(LatLng(p.lat,p.lon)));
    return [for(final g in groups)
      if(g.length==1)_stationMarker(g.first,now)
      else Marker(point:LatLng(g.map((p)=>p.lat).reduce((a,b)=>a+b)/g.length,g.map((p)=>p.lon).reduce((a,b)=>a+b)/g.length),width:46,height:46,
        child:Tooltip(message:g.map((p)=>p.label).join(', '),child:GestureDetector(onTap:()=>_fitPoints([for(final p in g)LatLng(p.lat,p.lon)]),
          child:Container(alignment:Alignment.center,decoration:BoxDecoration(color:s.surface,shape:BoxShape.circle,border:Border.all(color:s.secondary,width:2.5)),
            child:Text('${g.length}',style:TextStyle(fontWeight:FontWeight.w800,color:s.onSurface)))))),
    ];
  }

  Marker _stationMarker(SarcadePosition p,DateTime now){
    final s=Theme.of(context).colorScheme;
    final f=freshness(p.time.toUtc(),now,ageingMin:_ageingMin,staleMin:_staleMin);
    return Marker(point:LatLng(p.lat,p.lon),width:170,height:64,alignment:Alignment.topCenter,child:GestureDetector(onTap:()=>_select(p,move:false),
      child:Opacity(opacity:f==Freshness.ageing?0.75:1,child:Column(mainAxisSize:MainAxisSize.min,children:[
        _stationIcon(p),const SizedBox(height:2),
        Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
          decoration:BoxDecoration(color:s.surface.withValues(alpha:0.92),borderRadius:BorderRadius.circular(6),border:Border.all(color:_selectedDevice==p.deviceId?_stationColor(p):s.outlineVariant)),
          child:Text.rich(TextSpan(children:[
            TextSpan(text:p.label,style:TextStyle(fontWeight:FontWeight.w700,decoration:f==Freshness.stale?TextDecoration.lineThrough:null)),
            TextSpan(text:'  ${ageLabel(p.time.toUtc(),now)}',style:TextStyle(color:f==Freshness.fresh?_stationColor(p):s.tertiary)),
          ]),style:TextStyle(fontSize:11,color:s.onSurface),maxLines:1,overflow:TextOverflow.ellipsis)),
      ]))));
  }

  String _sourceLabel(SarcadePosition p)=>switch(sourceOf(p)){
    PositionSource.app=>S.t('source.app'),PositionSource.aprsRadio=>S.t('source.radio'),PositionSource.aprsInternet=>S.t('source.internet')};

  Widget _stationTile(SarcadePosition p){
    final now=DateTime.now().toUtc(); final s=Theme.of(context).colorScheme;
    final f=freshness(p.time.toUtc(),now,ageingMin:_ageingMin,staleMin:_staleMin); final fav=_favourites.contains(p.deviceId);
    return ListTile(selected:_selectedDevice==p.deviceId,leading:_stationIcon(p,size:32),
      title:Text(p.label,style:TextStyle(decoration:f==Freshness.stale?TextDecoration.lineThrough:null)),
      subtitle:Text('${_sourceLabel(p)} · ${ageLabel(p.time.toUtc(),now)}',style:TextStyle(color:f==Freshness.fresh?null:s.tertiary)),
      trailing:IconButton(tooltip:S.t(fav?'favourites.remove':'favourites.add'),onPressed:()=>_toggleFavourite(p.deviceId),
        icon:Icon(fav?Icons.star:Icons.star_border,color:fav?s.tertiary:null)),
      onTap:()=>_select(p));
  }

  /// Station sheet (aprs.fi): source and path, trace 1 h / 6 h / 24 h with
  /// a time cursor.
  Widget _stationSheet(SarcadePosition p){
    final s=Theme.of(context).colorScheme; final now=DateTime.now().toUtc(); final fav=_favourites.contains(p.deviceId);
    final f=freshness(p.time.toUtc(),now,ageingMin:_ageingMin,staleMin:_staleMin);
    String hm(DateTime t){final l=t.toLocal();return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';}
    final details=[
      if(p.speedMps!=null)'${(p.speedMps!*3.6).toStringAsFixed(0)} km/h',
      if(p.headingDeg!=null)'${S.t('station.heading')} ${p.headingDeg!.toStringAsFixed(0).padLeft(3,'0')}°',
      if(p.altM!=null)'${p.altM!.toStringAsFixed(0)} m',
      f==Freshness.stale?'${ageLabel(p.time.toUtc(),now)} · ${hm(p.time)}':ageLabel(p.time.toUtc(),now),
    ];
    return Container(padding:const EdgeInsets.all(14),decoration:glass(context,radius:18,border:_stationColor(p).withValues(alpha:0.6)),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          _stationIcon(p,size:40),const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(p.label,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            Text(details.join(' · '),style:TextStyle(fontSize:12,color:f==Freshness.fresh?s.onSurfaceVariant:s.tertiary)),
          ])),
          IconButton(tooltip:S.t(fav?'favourites.remove':'favourites.add'),onPressed:()=>_toggleFavourite(p.deviceId),icon:Icon(fav?Icons.star:Icons.star_border,color:fav?s.tertiary:null)),
          IconButton(tooltip:S.t('common.close'),onPressed:()=>setState((){_selectedDevice=null;_trace=[];_history=[];_scrub=null;}),icon:const Icon(Icons.close)),
        ]),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),decoration:BoxDecoration(color:s.surfaceContainerHigh,borderRadius:BorderRadius.circular(10)),
          child:Text([_sourceLabel(p),if(p.aprsPath?.isNotEmpty==true)S.t('station.via',{'path':p.aprsPath})].join(' · '),style:const TextStyle(fontSize:12,fontFamily:'monospace'))),
        const SizedBox(height:8),
        Row(children:[
          Text(S.t('station.trace'),style:const TextStyle(fontSize:13)),const SizedBox(width:8),
          for(final h in const [1,6,24])Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text('$h h'),selected:_traceHours==h,onSelected:(_)=>_setTraceHours(h),visualDensity:VisualDensity.compact)),
          if(_traceLoading)const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
        ]),
        if(_trace.length>1)...[
          Slider(min:0,max:(_trace.length-1).toDouble(),divisions:_trace.length-1,
            value:(_scrub==null?_trace.length-1:_trace.indexOf(_scrub!).clamp(0,_trace.length-1)).toDouble(),
            label:hm((_scrub??_trace.last).time),
            onChanged:(v)=>setState(()=>_scrub=_trace[v.round()])),
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Text(hm(_trace.first.time),style:const TextStyle(fontSize:11)),
            Text(hm((_scrub??_trace.last).time),style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:s.secondary)),
            Text(hm(_trace.last.time),style:const TextStyle(fontSize:11)),
          ]),
        ]else if(!_traceLoading)Text(S.t('station.noTrace'),style:TextStyle(fontSize:12,color:s.onSurfaceVariant)),
      ]));
  }

  /// « Données de 14:32, il y a 6 min » when this device received nothing
  /// for more than 2 minutes.
  Widget? _staleBanner(){
    final last=_sync.lastServerContact;
    if(!_started||last==null)return null;
    final age=DateTime.now().difference(last);
    if(age.inMinutes<2)return null;
    final s=Theme.of(context).colorScheme;
    final hm='${last.hour.toString().padLeft(2,'0')}:${last.minute.toString().padLeft(2,'0')}';
    return Container(height:32,padding:const EdgeInsets.symmetric(horizontal:12),
      decoration:BoxDecoration(color:s.tertiaryContainer,borderRadius:BorderRadius.circular(16),border:Border.all(color:s.tertiary)),
      child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.history,size:16,color:s.tertiary),const SizedBox(width:6),
        Text(S.t('stale.banner',{'time':hm,'age':ageLabel(last.toUtc(),DateTime.now().toUtc())}),style:TextStyle(fontSize:12,color:s.onTertiaryContainer))]));
  }

  /// « À proximité » (Tesla): from the search pin, else the measure target,
  /// else the map centre; operators, stations and reference sites.
  Widget _nearbyPanel(){
    final s=Theme.of(context).colorScheme;
    final from=_searchPin??_measure.target??_mapCentre();
    final fromLabel=_searchPin!=null?S.t('nearby.fromPin'):_measure.target!=null?S.t('nearby.fromTarget'):S.t('nearby.fromCentre');
    final items=<({String title,String subtitle,LatLng at,Widget icon,VoidCallback onTap})>[
      for(final p in _positions.values)(title:p.label,subtitle:'${_sourceLabel(p)} · ${ageLabel(p.time.toUtc(),DateTime.now().toUtc())}',at:LatLng(p.lat,p.lon),icon:_stationIcon(p,size:30),onTap:()=>_select(p)),
      for(final r in _references.values)(title:r.name,subtitle:r.subtitle,at:LatLng(r.lat,r.lon),icon:Icon(r.isHighPoint?Icons.terrain:Icons.cell_tower,color:s.secondary),onTap:()=>_selectReference(r)),
    ];
    final list=from==null?<Nearby<({String title,String subtitle,LatLng at,Widget icon,VoidCallback onTap})>>[]:nearest(from,items,(i)=>i.at);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(14,12,6,0),child:Row(children:[
        Expanded(child:Text(S.t('nearby.title'),style:Theme.of(context).textTheme.titleMedium)),
        IconButton(tooltip:S.t('common.close'),onPressed:()=>setState(()=>_showNearby=false),icon:const Icon(Icons.close)),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Text(fromLabel,style:TextStyle(fontSize:12,color:s.onSurfaceVariant))),
      const SizedBox(height:6),
      Expanded(child:ListView(children:[for(final n in list)ListTile(leading:SizedBox(width:34,child:Center(child:n.item.icon)),
        title:Text(n.item.title,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text(n.item.subtitle,maxLines:1,overflow:TextOverflow.ellipsis),
        trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
          Text(geo.formatDistance(n.distanceM),style:const TextStyle(fontWeight:FontWeight.w700)),
          Text('Az ${n.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}°',style:TextStyle(fontSize:11,color:s.onSurfaceVariant)),
        ]),onTap:n.item.onTap)])),
    ]);
  }

  // --- Bearings (note « Relevés et croisements », screen V2) ---
  late final BearingController _bearings;
  final _brgTarget=TextEditingController(); int _brgStrength=0;
  bool get _showBearings=>widget.store.preference('show_brg:${widget.eventId}')!='0';
  String get _brgSearch=>widget.store.preference('brg_search:${widget.eventId}')??'';

  void _initBearings(){
    _bearings=BearingController(eventId:widget.eventId,actorId:widget.deviceId,location:_location,
      onSave:(b,{required isNew}) async {
        await widget.store.saveMapFeature(b.toJson());
        await _sync.queue(objectId:b.id,objectType:'map_feature',action:isNew?'create':'update',payload:b.toJson());
      },
      onDelete:(b) async {
        await widget.store.deleteMapFeature(b.id);
        await _sync.queue(objectId:b.id,objectType:'map_feature',action:'delete',payload:{
          'id':b.id,'event_id':widget.eventId,'updated_by':widget.deviceId,'updated_at':DateTime.now().toUtc().toIso8601String()});
      });
    for(final j in widget.store.mapFeatures(widget.eventId)){
      if(!Bearing.isBearing(j)||j['deleted']==true)continue;
      try{_bearings.applyRemote(Bearing.fromJson(j));}catch(_){}
    }
    _bearings.addListener((){if(mounted)setState((){});});
  }

  Bearing? _bearingDraft()=>_bearings.taking?_bearings.draft(target:_brgTarget.text.trim(),strength:_brgStrength,search:_brgSearch):null;

  /// Top of the screen while taking a bearing: azimuth in big figures,
  /// position, accuracy, time (direction-finding app of the captures).
  Widget _bearingHud(){
    final s=Theme.of(context).colorScheme; final b=_bearings; final az=b.trueDeg; final p=b.position;
    final t=DateTime.now(); String two(int v)=>v.toString().padLeft(2,'0');
    return Container(padding:const EdgeInsets.fromLTRB(14,10,8,10),decoration:glass(context,border:s.primary.withValues(alpha:0.6)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
        Row(children:[
          Expanded(child:Text(S.t(b.hasCompass||b.manualDeg!=null?'bearings.aim':'bearings.noCompass'),style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,letterSpacing:0.8,color:s.primary))),
          IconButton(tooltip:S.t('common.cancel'),onPressed:_bearings.stopTaking,icon:const Icon(Icons.close)),
        ]),
        Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Text(az==null?'—':'${az.toStringAsFixed(0).padLeft(3,'0')}°',style:const TextStyle(fontSize:60,fontWeight:FontWeight.w500,height:1,fontFeatures:[FontFeature.tabularFigures()])),
          const SizedBox(width:10),
          Padding(padding:const EdgeInsets.only(bottom:6),child:Text([S.t(b.manualDeg!=null?'bearings.typed':'bearings.true'),
            if(b.magneticDeg!=null&&b.manualDeg==null)S.t('bearings.magnetic',{'v':b.magneticDeg!.toStringAsFixed(0).padLeft(3,'0')})].join('\n'),
            style:TextStyle(fontSize:12,color:s.onSurfaceVariant))),
        ]),
        const SizedBox(height:4),
        Text([p==null?S.t('bearings.noPosition'):'${p.latitude.toStringAsFixed(4)}° N · ${p.longitude.toStringAsFixed(4)}° E',
          if(b.accuracyM!=null)'±${b.accuracyM!.toStringAsFixed(0)} m','${two(t.hour)}:${two(t.minute)}:${two(t.second)}'].join(' · '),
          style:TextStyle(fontSize:12,fontFamily:'monospace',color:s.onSurfaceVariant)),
      ]));
  }

  /// Bottom of the screen while taking a bearing: target, strength S1–S9,
  /// search, effect on the probable zone, « Enregistrer le relevé ».
  Widget _bearingTakeSheet(){
    final s=Theme.of(context).colorScheme;
    final draft=_bearingDraft();
    final same=_bearings.all.where((b)=>b.search==_brgSearch).toList();
    final before=probableZone(same), after=draft==null?null:probableZone([...same,draft]);
    final effect=before.centre!=null&&after?.centre!=null?S.t('bearings.effect',{'a':geo.formatDistance(before.radiusM),'b':geo.formatDistance(after!.radiusM)})
      :after?.centre!=null?S.t('bearings.firstZone',{'b':geo.formatDistance(after!.radiusM)}):null;
    return Container(padding:const EdgeInsets.all(14),decoration:glass(context,radius:22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Expanded(child:TextField(controller:_brgTarget,onChanged:(_)=>setState((){}),decoration:InputDecoration(labelText:S.t('bearings.target'),hintText:'121,500 MHz',isDense:true,border:const OutlineInputBorder()))),
        const SizedBox(width:8),
        Expanded(child:InkWell(onTap:_chooseSearch,child:InputDecorator(decoration:InputDecoration(labelText:S.t('bearings.search'),isDense:true,border:const OutlineInputBorder()),
          child:Row(children:[Container(width:10,height:10,decoration:BoxDecoration(color:Color(searchColor(_brgSearch)),shape:BoxShape.circle)),const SizedBox(width:6),
            Expanded(child:Text(_brgSearch.isEmpty?S.t('bearings.searchNone'):_brgSearch,overflow:TextOverflow.ellipsis))])))),
      ]),
      const SizedBox(height:10),
      Row(children:[
        Text(S.t('bearings.strength'),style:const TextStyle(fontSize:13)),const SizedBox(width:8),
        Expanded(child:Row(children:[for(var i=1;i<=9;i++)Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:1.5),child:Semantics(button:true,label:'S$i',selected:_brgStrength==i,
          child:InkWell(onTap:()=>setState(()=>_brgStrength=_brgStrength==i?0:i),child:Container(height:22,decoration:BoxDecoration(
            color:i<=_brgStrength?s.primary:s.surfaceContainerHighest,borderRadius:BorderRadius.circular(4)))))))])),
        const SizedBox(width:8),
        SizedBox(width:28,child:Text(_brgStrength==0?'—':'S$_brgStrength',style:TextStyle(fontWeight:FontWeight.w700,color:s.primary))),
      ]),
      if(effect!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(effect,style:TextStyle(fontSize:13,color:s.onSurfaceVariant))),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52)),
          onPressed:draft==null?null:() async {
            final b=await _bearings.save(target:_brgTarget.text.trim(),strength:_brgStrength,search:_brgSearch);
            if(b!=null&&mounted){_brgTarget.clear();setState(()=>_brgStrength=0);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('bearings.saved',{'v':b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}))));}
          },
          icon:const Icon(Icons.track_changes),label:Text(S.t('bearings.save')))),
        const SizedBox(width:8),
        IconButton.outlined(tooltip:S.t('bearings.typeAzimuth'),style:IconButton.styleFrom(fixedSize:const Size(52,52)),onPressed:_typeAzimuth,icon:const Icon(Icons.edit_outlined)),
        const SizedBox(width:4),
        IconButton.outlined(tooltip:S.t('bearings.useMapCentre'),style:IconButton.styleFrom(fixedSize:const Size(52,52)),
          onPressed:(){final c=_mapCentre();if(c!=null)_bearings.setPosition(c);},icon:const Icon(Icons.filter_center_focus)),
      ]),
    ]));
  }

  Future<void> _typeAzimuth() async {
    final ctrl=TextEditingController(text:_bearings.trueDeg?.toStringAsFixed(0)??'');
    final v=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('bearings.typeAzimuth')),
      content:TextField(controller:ctrl,autofocus:true,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(suffixText:'°',helperText:S.t('bearings.typeHelp'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text),child:Text(S.t('common.ok')))]));
    ctrl.dispose();
    if(v==null)return;
    final d=double.tryParse(v.replaceAll(',','.').trim());
    _bearings.setManual(d==null||d<0||d>360?null:d);
  }

  Future<void> _chooseSearch() async {
    final names={for(final b in _bearings.all)b.search}..remove('');
    final ctrl=TextEditingController();
    final v=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('bearings.search')),children:[
      SimpleDialogOption(onPressed:()=>Navigator.pop(c,''),child:Text(S.t('bearings.searchNone'))),
      for(final n in names)SimpleDialogOption(onPressed:()=>Navigator.pop(c,n),child:Row(children:[Icon(Icons.circle,size:12,color:Color(searchColor(n))),const SizedBox(width:8),Text(n)])),
      Padding(padding:const EdgeInsets.fromLTRB(24,8,24,8),child:TextField(controller:ctrl,decoration:InputDecoration(labelText:S.t('bearings.searchNew'),hintText:'Balise 406 – 27/10'),
        onSubmitted:(t)=>Navigator.pop(c,t.trim()))),
    ]));
    ctrl.dispose();
    if(v==null)return;
    await widget.store.setPreference('brg_search:${widget.eventId}',v.isEmpty?null:v);
    if(mounted)setState((){});
  }

  /// Details of a bearing; change or delete for its author or the PCO.
  Future<void> _showBearingSheet(Bearing b) async {
    final can=b.canEdit(widget.deviceId,isPco(widget.deviceId));
    final l=b.takenAt.toLocal(); String two(int v)=>v.toString().padLeft(2,'0');
    final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,0,20,12),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}° ${S.t('bearings.true')}',style:const TextStyle(fontSize:32,fontWeight:FontWeight.w600)),
        Text([b.createdBy,'${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}',if(b.strength>0)'S${b.strength}',if(b.target.isNotEmpty)b.target,
          S.t('bearings.method.${b.method}'),if(b.search.isNotEmpty)b.search].join(' · ')),
        if(b.comment.isNotEmpty)Padding(padding:const EdgeInsets.only(top:6),child:Text(b.comment)),
        Text(S.t('bearings.lineCone',{'l':geo.formatDistance(b.lengthM),'c':b.coneDeg.toStringAsFixed(0)}),style:TextStyle(fontSize:12,color:Theme.of(c).colorScheme.onSurfaceVariant)),
        const SizedBox(height:8),
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.place_outlined),title:Text(S.t('bearings.fromOrigin')),onTap:()=>Navigator.pop(c,'origin')),
        if(can)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.edit_outlined),title:Text(S.t('bearings.edit')),onTap:()=>Navigator.pop(c,'edit')),
        if(can)ListTile(contentPadding:EdgeInsets.zero,leading:Icon(Icons.delete_outline,color:Theme.of(c).colorScheme.error),title:Text(S.t('bearings.delete')),onTap:()=>Navigator.pop(c,'delete')),
      ]))));
    if(!mounted)return;
    if(choice=='origin'){await _onLongPress(b.origin);return;}
    if(choice=='delete'){
      final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(content:Text(S.t('bearings.deleteConfirm')),actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('bearings.delete')))]));
      if(ok==true)await _bearings.delete(b);
    }
    if(choice=='edit')await _editBearing(b);
  }

  Future<void> _editBearing(Bearing b) async {
    final az=TextEditingController(text:b.azimuthDeg.toStringAsFixed(1)), cone=TextEditingController(text:b.coneDeg.toStringAsFixed(0)),
      len=TextEditingController(text:(b.lengthM/1000).toStringAsFixed(1)), target=TextEditingController(text:b.target), comment=TextEditingController(text:b.comment);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('bearings.edit')),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:az,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:S.t('bearings.azimuth'),suffixText:'°')),
      TextField(controller:cone,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:S.t('bearings.cone'),suffixText:'± °')),
      TextField(controller:len,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:S.t('bearings.length'),suffixText:'km')),
      TextField(controller:target,decoration:InputDecoration(labelText:S.t('bearings.target'))),
      TextField(controller:comment,decoration:InputDecoration(labelText:S.t('bearings.comment'))),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.save')))]));
    double? n(TextEditingController t)=>double.tryParse(t.text.replaceAll(',','.').trim());
    if(ok==true){
      final a=n(az),cn=n(cone),ln=n(len);
      await _bearings.update(b.copyWith(azimuthDeg:a==null||a<0||a>360?null:a%360,coneDeg:cn==null||cn<0||cn>45?null:cn,
        lengthM:ln==null||ln<0.1||ln>200?null:ln*1000,target:target.text.trim(),comment:comment.text.trim(),
        updatedBy:widget.deviceId,updatedAt:DateTime.now().toUtc()));
    }
    for(final t in [az,cone,len,target,comment]){t.dispose();}
  }

  // The dialog owns its text controller: disposing it when the Future
  // completed freed it while the closing animation still used it
  // ('_dependents.isEmpty' assertion, Windows test of 13 Oct 2026).
  Future<String?> _askText({required String title,required String initial})=>
    showDialog<String>(context:context,builder:(_)=>_TextPromptDialog(title:title,initial:initial));

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

  @override void dispose(){_saveViewTimer?.cancel();_bearings.dispose();_brgTarget.dispose();_positionsTimer?.cancel();_meSub?.cancel();_mapEvents?.cancel();AccessManager.instance.removeListener(_onAccessChanged);_rtSub?.cancel();_tracking.removeListener(_onOperationsChanged);_ops.removeListener(_onOperationsChanged);_tracking.dispose();_ops.dispose();_routes.removeListener(_onRoutesChanged);_nav.removeListener(_onRoutesChanged);_routes.dispose();_nav.dispose();_measure.removeListener(_onRoutesChanged);_measure.dispose();_syncUiTimer?.cancel();_sync.dispose();_realtime.dispose();_drawing.dispose();widget.api.close();super.dispose();}

  @override Widget build(BuildContext context){
    final sorted=_positions.values.where((p)=>(p.isAprs?_showAprs:_showOperators)&&(!_withoutInternetOnly||worksWithoutInternet(p)||p.deviceId==widget.deviceId)).toList()..sort((a,b)=>a.deviceId.compareTo(b.deviceId));
    final markers=<Marker>[
      ..._stationMarkers(sorted),
      ..._pois.values.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:40,height:40,child:Tooltip(message:p.label??p.kind,child:const Icon(Icons.location_on,size:38,color:Colors.red)))),
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
    void openMessages()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId,sync:_sync,store:widget.store)));
    void showMap()=>setState((){_showPanel=false;_showReferencePanel=false;_showRoutesPanel=false;_showNearby=false;_drawingRouteId=null;});
    // Every action of the former top bar, for the « Plus » sheet (phone) and the rail (computer).
    final actions=<_RailAction>[
      _RailAction(Icons.groups_outlined,S.t('map.operators'),toggleOperators,selected:_showPanel),
      _RailAction(Icons.cell_tower,S.t('map.references'),toggleReferences,selected:_showReferencePanel),
      _RailAction(Icons.track_changes,S.t('bearings.take'),()=>_bearings.startTaking()),
      _RailAction(Icons.near_me_outlined,S.t('nearby.title'),()=>setState((){_showNearby=!_showNearby;if(_showNearby){_showPanel=false;_showReferencePanel=false;_showRoutesPanel=false;}}),selected:_showNearby),
      _RailAction(Icons.route,S.t('routes.menu'),toggleRoutes,selected:_showRoutesPanel),
      _RailAction(Icons.cloud_outlined,S.t('weather.menu'),()=>_openWeather()),
      _RailAction(Icons.pin_drop_outlined,S.t('measure.goto'),_gotoCoordinates),
      _RailAction(Icons.center_focus_strong,S.t('map.fit'),_fitOperators),
      _RailAction(Icons.folder_copy_outlined,S.t('map.files'),openFiles),
      _RailAction(Icons.receipt_long,S.t('map.logbook'),openLogbook),
      _RailAction(Icons.outbox_outlined,'${S.t('unsent.title')} (${_sync.unsent})',_openUnsent),
    ];
    void openMore()=>showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      for(final a in actions)ListTile(leading:Icon(a.icon),title:Text(a.label),selected:a.selected,onTap:(){Navigator.pop(c);a.onTap();}),
      ListTile(leading:Icon(Theme.of(context).brightness==Brightness.dark?Icons.light_mode_outlined:Icons.dark_mode_outlined),title:Text(S.t('ui.dayNight')),onTap:(){Navigator.pop(c);_toggleDayNight();}),
      if(widget.onSettings!=null)ListTile(leading:const Icon(Icons.settings_outlined),title:Text(S.t('map.settings')),onTap:(){Navigator.pop(c);widget.onSettings!();}),
    ]))));
    final messagesButton=IconButton(tooltip:S.t('map.messages'),onPressed:openMessages,icon:_messagesIcon());
    return Scaffold(
      body:SafeArea(bottom:false,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        OperationsBanners(settings:_ops.settings,update:_ops.update,
          alert:syncAlert(_sync.currentItems,DateTime.now(),_ops.settings.syncAlertMinutes),
          heldPhotos:_sync.lowBandwidth?widget.store.pendingUploads().length:0,
          onSyncNow:() async {await _sync.syncNow();if(mounted)setState((){});},
          onUpdate:()=>downloadUpdate(context,widget.api,_ops.update),
          accessRequired:AccessManager.instance.requiredFor(widget.api.baseUrl),
          accessRenewBy:_accessRenewBy,onSignIn:_signIn,
          onReload:isWebPlatform&&!_sync.lastSyncOk&&_sync.lastServerContact!=null&&browserOnline?reloadApp:null,
          onEnableNotifications:_notificationsBanner?_enableNotifications:null,
          onDismissNotifications:()=>setState(()=>_notificationsDismissed=true)),
        Expanded(child:_withDrawingShortcuts(Row(children:[
        // Computer: rail on the left (mock-up V2).
        if(!compact)_Rail(messages:messagesButton,actions:actions,onMap:showMap,mapSelected:!_showPanel&&!_showReferencePanel&&!_showRoutesPanel,
          onDayNight:_toggleDayNight,onSettings:widget.onSettings,status:_statusLine,statusColor:_statusColor,onStatus:_openUnsent),
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
            if(r.callsign?.isNotEmpty==true)Text(S.t(r.isHighPoint?'refs.reference':'refs.callsign',{'v':r.callsign})),
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
          Expanded(child:ListView(children:sortStations(sorted,_favourites).map((p)=>_stationTile(p)).toList())),
        ]))),
        if(_showNearby)SizedBox(width:panelWidth(340),child:Material(elevation:3,child:_nearbyPanel())),
        Expanded(child:Stack(key:_mapKey,children:[FlutterMap(mapController:_map,options:MapOptions(
          initialCenter:_savedView==null?const LatLng(48.8566,2.3522):LatLng(_savedView.lat,_savedView.lon),initialZoom:_savedView?.zoom??11,maxZoom:20,onTap:_onMapTap,
          onPositionChanged:(camera,_)=>_onCameraChanged(camera),
          onLongPress:(_,point)=>_onLongPress(point),
          onSecondaryTap:(_,point)=>_onLongPress(point),
          // Rotation off: drawn arrows and handles assume north up.
          // Drag off while editing so handle and freehand gestures reach the shapes.
          interactionOptions:InteractionOptions(flags:InteractiveFlag.all&~InteractiveFlag.rotate&(_drawing.locksMapDrag?~InteractiveFlag.drag:~0)),
        ),children:[
          // Night: street maps darkened; aerial photos stay as they are.
          TileLayer(key:ValueKey('$_tileUrl|${_darkTiles(context)}'),urlTemplate:_tileUrl,userAgentPackageName:'org.sarcade.app',maxZoom:_basemap.maxZoom.toDouble(),
            tileBuilder:_darkTiles(context)?darkModeTileBuilder:null),
          if(_trace.length>1)PolylineLayer(polylines:_traceSegments().map((segment)=>Polyline(points:segment.map((p)=>LatLng(p.lat,p.lon)).toList(),strokeWidth:4,color:Theme.of(context).colorScheme.secondary)).toList()),
          // Reference sites below the drawn objects, grouped when zoomed out.
          ReferenceClusterLayer(sites:_references.values.where((r)=>(r.isHighPoint&&_showHighPoints)||(r.isRelay&&_showRelays)).toList(),onSelect:_selectReference),
          if(_showDrawings)...buildDrawingLayers(_drawing),
          if(_showBearings||_bearings.taking)...buildBearingLayers(bearings:_showBearings?_bearings.all:const <Bearing>[],draft:_bearingDraft(),
            onTapBearing:_showBearingSheet,onTapZone:(c,_)=>_onLongPress(c)),
          ...buildRouteLayers(_routes,selectedRouteId:_selectedRouteId,itinerary:_nav.itinerary?.geometry??const [],draftClosure:_closureDraft,
            onWaypointTap:(w)=>setState((){_showRoutesPanel=true;_showPanel=false;_showReferencePanel=false;_selectedRouteId=w.routeId;})),
          ...buildMeasureLayers(_measure,_coordFormat),
          MarkerLayer(markers:markers),
          if(_me!=null)MarkerLayer(markers:[Marker(point:_me!,width:22,height:22,child:Container(decoration:BoxDecoration(color:Colors.blue,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:3),boxShadow:const [BoxShadow(blurRadius:4,color:Colors.black26)])))]),
          if(_trace.isNotEmpty)MarkerLayer(markers:[for(final t in _trace)Marker(point:LatLng(t.lat,t.lon),width:8,height:8,
            child:Container(decoration:BoxDecoration(color:Theme.of(context).colorScheme.secondary,shape:BoxShape.circle)))]),
          if(_scrub!=null)MarkerLayer(markers:[Marker(point:LatLng(_scrub!.lat,_scrub!.lon),width:22,height:22,
            child:Container(decoration:BoxDecoration(color:Theme.of(context).colorScheme.onSecondaryContainer,shape:BoxShape.circle,border:Border.all(color:Theme.of(context).colorScheme.secondary,width:3))))]),
          if(_searchPin!=null)MarkerLayer(markers:[Marker(point:_searchPin!,width:44,height:44,alignment:Alignment.topCenter,
            child:GestureDetector(onTap:()=>_onLongPress(_searchPin!),child:const Icon(Icons.location_on,color:Colors.red,size:44)))]),
          buildHandleLayer(_drawing,_globalToLatLng),
          RichAttributionWidget(attributions:[TextSourceAttribution(_basemap.attribution.isEmpty?widget.tileAttribution:_basemap.attribution)]),
        ]),
        if(_drawing.tool==FeatureKind.freehand)Positioned.fill(child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onPanStart:_onFreehandStart,onPanUpdate:_onFreehandUpdate,onPanEnd:_onFreehandEnd,
          child:CustomPaint(painter:_StrokePainter(_stroke,Color(_drawing.color),_drawing.strokeWidth)),
        )),
        if(_bearings.taking)Positioned(top:8,left:8,right:8,child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:_bearingHud())))
        else Positioned(top:8,left:8,right:8,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          // The drawing button stays in place and toggles the toolbar
          // (request of 23 October 2026: closing it after a tap by mistake
          // meant reaching the small cross at the far right).
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            FloatingActionButton.small(heroTag:'drawing-tools',
              tooltip:_drawingTools?S.t('draw.close'):S.t('draw.open'),
              backgroundColor:_drawingTools?Theme.of(context).colorScheme.primary:null,
              foregroundColor:_drawingTools?Theme.of(context).colorScheme.onPrimary:null,
              onPressed:_toggleDrawingTools,
              child:Icon(_drawingTools?Icons.draw:Icons.draw_outlined)),
            if(_drawingTools)...[
              const SizedBox(width:8),
              Flexible(child:DrawingToolbar(controller:_drawing,onExport:_exportGeoJson,onImport:_importFile,onClose:_toggleDrawingTools)),
            ]else...[
              const SizedBox(width:8),
              Flexible(child:MapSearchBar(items:_searchables,addresses:_searchAddresses,near:_mapCentre,onPick:_onSearchPick)),
              const SizedBox(width:8),
              _linksPill(),
            ],
          ]),
          if(!_drawingTools)Padding(padding:const EdgeInsets.only(top:8),child:_filterChips()),
          if(!_drawingTools)Padding(padding:const EdgeInsets.only(top:8),child:Wrap(spacing:8,runSpacing:8,children:[_trackingBadge(),?_staleBanner()])),
          if(_drawing.isDrawing)Padding(padding:const EdgeInsets.only(top:8),child:DraftBar(controller:_drawing)),
          if(_drawing.selected!=null)Padding(padding:const EdgeInsets.only(top:8),child:SelectionBar(controller:_drawing,onEditLabel:_editSelectedLabel)),
          if(_drawingClosure)Padding(padding:const EdgeInsets.only(top:8),child:Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.block,color:Colors.red),const SizedBox(width:8),
            Flexible(child:Text(S.t('closures.drawHelp'))),
            TextButton(onPressed:()=>setState((){_drawingClosure=false;_closureDraft.clear();}),child:Text(S.t('closures.cancel'))),
            FilledButton(onPressed:_finishClosure,child:Text(S.t('closures.finish'))),
          ])))),
        ])),
        Positioned(right:12,bottom:compact?104:24,child:_mapButtons()),
        if(_bearings.taking)Positioned(left:0,right:0,bottom:compact?92:16,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:_bearingTakeSheet()))))
        else if(selected!=null)Positioned(left:12,right:compact?12:null,bottom:compact?96:24,
          child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:_stationSheet(selected))),
        Positioned(left:16,bottom:compact?108:24,child:IgnorePointer(child:_scaleBar())),
        // Phone: floating tab bar at the bottom (mock-up V2).
        if(compact)Positioned(left:12,right:12,bottom:12,child:SafeArea(top:false,child:_TabBar(
          messages:messagesButton,onMap:showMap,mapSelected:!_showPanel&&!_showReferencePanel&&!_showRoutesPanel,
          onTeams:toggleOperators,teamsSelected:_showPanel,onLogbook:openLogbook,onMore:openMore))),
        Positioned(left:0,right:0,bottom:compact?100:72,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Column(mainAxisSize:MainAxisSize.min,children:[
          MeasureCard(m:_measure,format:_coordFormat,onSavePoi:_savePoi,onSendMessage:_sendMeasure,
            onFit:(){final o=_measure.origin,t=_measure.target;if(t!=null)_fitPoints([?o?.point,t]);},
            onOpenElsewhere:(){final t=_measure.target;if(t!=null)openInOtherApp(context,t,_measure.targetLabel);},
            onChooseOrigin:_chooseOrigin,
            onFormat:(f) async {await widget.store.setPreference('coord_format',f.name);if(mounted)setState((){});}),
          NavigationCard(nav:_nav),
        ])))),
      ]))
      ]))),
      ])),
    );
  }
}

/// One action of the rail (computer) or of the « Plus » sheet (phone).
class _RailAction {
  final IconData icon; final String label; final VoidCallback onTap; final bool selected;
  const _RailAction(this.icon,this.label,this.onTap,{this.selected=false});
}

/// Computer: vertical rail on the left (mock-up V2).
class _Rail extends StatelessWidget {
  final Widget messages; final List<_RailAction> actions; final VoidCallback onMap, onDayNight, onStatus; final bool mapSelected;
  final VoidCallback? onSettings; final String status; final Color? statusColor;
  const _Rail({required this.messages,required this.actions,required this.onMap,required this.mapSelected,required this.onDayNight,
    required this.onSettings,required this.status,required this.statusColor,required this.onStatus});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    Widget button(IconData icon,String label,VoidCallback onTap,{bool selected=false})=>Padding(padding:const EdgeInsets.symmetric(vertical:3),
      child:IconButton(tooltip:label,onPressed:onTap,isSelected:selected,
        style:IconButton.styleFrom(fixedSize:const Size(48,48),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
          backgroundColor:selected?scheme.primaryContainer:null,foregroundColor:selected?scheme.primary:scheme.onSurfaceVariant),
        icon:Icon(icon)));
    return Container(width:72,margin:const EdgeInsets.fromLTRB(8,8,0,8),decoration:glass(context),
      child:Column(children:[
        const SizedBox(height:10),
        Tooltip(message:status,child:InkWell(onTap:onStatus,borderRadius:BorderRadius.circular(12),child:Container(width:40,height:40,alignment:Alignment.center,
          decoration:BoxDecoration(color:statusColor??scheme.primary,borderRadius:BorderRadius.circular(12)),
          child:Text('S',style:TextStyle(fontWeight:FontWeight.w800,fontSize:18,color:statusColor==null?scheme.onPrimary:Colors.white))))),
        const SizedBox(height:10),
        Expanded(child:SingleChildScrollView(child:Column(children:[
          button(Icons.map_outlined,S.t('tabs.map'),onMap,selected:mapSelected),
          Padding(padding:const EdgeInsets.symmetric(vertical:3),child:messages),
          for(final a in actions)button(a.icon,a.label,a.onTap,selected:a.selected),
        ]))),
        button(Theme.of(context).brightness==Brightness.dark?Icons.light_mode_outlined:Icons.dark_mode_outlined,S.t('ui.dayNight'),onDayNight),
        if(onSettings!=null)button(Icons.settings_outlined,S.t('map.settings'),onSettings!),
        const SizedBox(height:8),
      ]));
  }
}

/// Phone: floating tab bar at the bottom (Facebook, Meshtastic, Plex).
class _TabBar extends StatelessWidget {
  final Widget messages; final VoidCallback onMap, onTeams, onLogbook, onMore; final bool mapSelected, teamsSelected;
  const _TabBar({required this.messages,required this.onMap,required this.mapSelected,required this.onTeams,required this.teamsSelected,required this.onLogbook,required this.onMore});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    Widget tab(IconData icon,String label,VoidCallback onTap,{bool selected=false})=>Expanded(child:Tooltip(message:label,excludeFromSemantics:true,child:InkWell(
      onTap:onTap,borderRadius:BorderRadius.circular(28),
      child:Semantics(button:true,selected:selected,label:label,excludeSemantics:true,child:Container(height:56,
        decoration:BoxDecoration(color:selected?scheme.primaryContainer:null,borderRadius:BorderRadius.circular(28)),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(icon,color:selected?scheme.primary:scheme.onSurfaceVariant),
          Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,color:selected?scheme.primary:scheme.onSurfaceVariant)),
        ]))))));
    return Container(height:68,padding:const EdgeInsets.symmetric(horizontal:6),decoration:glass(context,radius:34),
      child:Row(children:[
        tab(Icons.map_outlined,S.t('tabs.map'),onMap,selected:mapSelected),
        Expanded(child:Center(child:messages)),
        tab(Icons.groups_outlined,S.t('tabs.teams'),onTeams,selected:teamsSelected),
        tab(Icons.receipt_long,S.t('tabs.logbook'),onLogbook),
        tab(Icons.more_horiz,S.t('tabs.more'),onMore),
      ]));
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


class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title,required this.initial});
  final String title, initial;
  @override State<_TextPromptDialog> createState()=>_TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller=TextEditingController(text:widget.initial);
  @override void dispose(){_controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.title),
    content:TextField(controller:_controller,autofocus:true,textCapitalization:TextCapitalization.sentences,maxLength:80,onSubmitted:(v)=>Navigator.pop(context,v)),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(context,_controller.text),child:Text(S.t('common.ok'))),
    ],
  );
}
