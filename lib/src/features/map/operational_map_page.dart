import 'dart:async';
import 'dart:math' as math;
import '../../ui/choice_pills.dart';
import '../messages/operator_avatar.dart';
import '../messages/conversations.dart' show avatarInitials;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:uuid/uuid.dart';

import '../../models/comm_group.dart';
import '../../models/message_reception.dart';
import '../../models/message_unread.dart';
import '../../models/web_update.dart';
import '../../config/version.dart';
import '../../models/poi.dart';
import '../poi/poi_sheet.dart';
import '../../models/message.dart';
import '../../models/position.dart';
import '../../models/reference_site.dart';
import '../messages/messages_page.dart';
import '../messages/messages_nav.dart';
import '../../services/notification_keys.dart';
import '../aprs/aprs_page.dart';
import '../search/map_search.dart';
import '../search/map_search_bar.dart';
import '../../ui/map_view.dart';
import '../../ui/test_ids.dart';
import '../../ui/compass_follow.dart';
import '../compass/shared_compass.dart';
import '../compass/compass_status.dart';
import '../measure/wmm.dart' show magneticDeclination;
import 'drawing/export_formats.dart';
import '../../ui/theme.dart';
import 'stations.dart';
import 'sos_placement.dart';
import '../bearings/bearing_aim.dart';
import '../../ui/escape_stack.dart';
import 'drawing/multi_select.dart';
import '../../offline/unsent_summary.dart';
import '../bearings/bearing_controller.dart';
import '../bearings/bearing_layers.dart';
import '../bearings/bearing_mouse_hud.dart';
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
import '../../services/wakeup_fcm.dart';
import '../../services/wakeup_state.dart';
import '../../services/notification_service.dart';
import '../../services/location_service.dart';
import '../../services/power_state.dart';
import '../../services/realtime_service.dart';
import '../../services/sarcade_api.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../access/access_login_page.dart';
import '../../access/access_manager.dart';
import '../../platform/platform_services.dart';
import '../../l10n/strings.dart';
import '../../operations/event_settings.dart';
import '../../operations/operations_service.dart';
import '../../operations/operations_widgets.dart';
import 'sos_alert.dart';
import '../../operations/tracking_service.dart';
import '../navigation/navigation_controller.dart';
import '../navigation/road_graph_service.dart';
import '../basemaps/basemap_models.dart';
import '../basemaps/basemap_sheet.dart';
import '../weather/weather_page.dart';
import '../weather/weather_models.dart';
import '../measure/coordinates.dart';
import '../measure/external_maps.dart';
import '../measure/measure_controller.dart';
import '../measure/measure_widgets.dart';
import '../navigation/navigation_widgets.dart';
import '../navigation/follow_mode.dart';
import '../navigation/point_label.dart';
import '../routes/route_models.dart';
import '../routes/routes_controller.dart';
import '../routes/routes_layers.dart';
import '../routes/route_entry_bar.dart';
import '../routes/routes_panel.dart';
import '../tv/tv_view.dart';
import '../tv/tv_nearby.dart';
import '../tv/tv_screens_button.dart';
import 'fixed_stations.dart';
import '../orders/move_orders.dart';
import '../bearings/signals.dart';
import '../settings/diagnostics_panel.dart' show diagnosticsAlert, showDiagnosticsSheet;
import '../tools/tools_page.dart';
import 'sos_button.dart';
import '../tools/coordinate_converter_page.dart';
import '../places/readable_place.dart';
import '../measure/point_info_open.dart';
import '../aprs/callsign_links.dart';
import '../tools/resection.dart';
import '../tools/resection_panel.dart';
import '../tv/tv_screens_page.dart';
import 'layer_row.dart';
import 'link_weather_pill.dart';
import 'locate_button.dart';
import 'locate_cycle.dart';
import 'point_menu.dart';
import 'map_objects.dart';
import 'traces_layer.dart';
import '../poi/poi_icons.dart';
import '../poi/poi_list.dart';
import '../routes/waypoint_sheet.dart';
import '../../ui/action_buttons.dart';
import '../../ui/link_status.dart';

class OperationalMapPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,deviceId,tileUrl,tileAttribution; final LocalStore store; final VoidCallback? onSettings;
  /// Computer: Paramètres opens beside the rail (decision of 29 Oct 2026).
  final Widget Function()? settingsBuilder;
  /// Operator settings sent with the heartbeat (APRS callsign and consent).
  final String callsign; final bool aprsTxConsent;
  /// The server announced its HTTPS address (the application tries it).
  final void Function(String httpsUrl)? onHttpsAvailable;
  /// Platform name sent to the server (« windows », « android », « web »…).
  final String platform;
  const OperationalMapPage({super.key,required this.api,required this.eventId,required this.deviceId,required this.store,required this.tileUrl,required this.tileAttribution,this.onSettings,this.settingsBuilder,
    this.callsign='',this.aprsTxConsent=false,this.platform='unknown',this.onHttpsAvailable});
  @override State<OperationalMapPage> createState()=>_OperationalMapPageState();
}

class _OperationalMapPageState extends State<OperationalMapPage> {
  final _map=MapController(); final _realtime=RealtimeService(); final _location=LocationService(); final _notifications=NotificationService(); final _uuid=const Uuid();
  final Map<String,SarcadePosition> _positions={}; final Map<String,SarcadePoi> _pois={}; final Map<String,ReferenceSite> _references={};
  StreamSubscription? _rtSub; Timer? _syncUiTimer; bool _started=false, _starting=false; bool _showPanel=false; /* closed at start on every screen: the map first (bug of 29 Oct 2026) */ bool _showReferencePanel=false; bool _showHighPointsPref=false; bool _showRelaysPref=false; /* off at start: decision of the project owner, 28 Oct 2026 */ String? _selectedDevice; ReferenceSite? _selectedReference; List<SarcadePosition> _trace=[]; bool _traceLoading=false; late final OfflineSyncService _sync; bool _layoutInitialized=false;
  late final DrawingController _drawing; bool _drawingTools=false; final _mapKey=GlobalKey();
  late final TrackingService _tracking; late final OperationsService _ops; bool _updatePageShown=false;
  late final RoutesController _routes; late final NavigationController _nav; late final RoadGraphService _graphs;
  List<Basemap> _catalog=builtInBasemaps;
  /// APRS stations followed by the event (the server only sends those).
  bool _showAprsPref=true;
  /// ADRASEC module of the event (card « Séparer le Core et les modules »,
  /// 31 Oct 2026): without it, no bearing, resection, APRS, fixed stations
  /// nor reference sites (high points, relays) anywhere on this screen.
  bool get _adrasec=>_ops.settings.moduleOn('adrasec');
  bool get _showAprs=>_showAprsPref&&_adrasec;
  bool get _showHighPoints=>_showHighPointsPref&&_adrasec;
  bool get _showRelays=>_showRelaysPref&&_adrasec;
  late final MeasureController _measure; bool _pickingOrigin=false;
  CoordFormat get _coordFormat=>coordFormatFrom(widget.store.preference('coord_format'));
  int get _mgrsDigits=>widget.store.preference('mgrs_digits')=='5'?5:4;
  bool _showRoutesPanel=false; String? _selectedRouteId, _drawingRouteId; bool _drawingClosure=false; final List<LatLng> _closureDraft=[];
  final List<Offset> _stroke=[];

  // Phones get the map full width: side panels start closed and open as overlays.
  static const _compactWidth=600.0;
  /// Phone: screen shown (note « Navigation et menus simplifiés », 27 Oct
  /// 2026): 0 Carte, 1 Messages, 2 Équipes, 3 Outils (decision of 30 Oct 2026, 3 h 10), 4 Plus. Each
  /// one is built at its first visit and then kept as it was left.
  int _tab=0; final Set<int> _builtTabs={0};
  bool get _isCompact=>MediaQuery.sizeOf(context).width<_compactWidth;
  void _goTab(int t){if(_tab==t)return;setState((){_tab=t;_builtTabs.add(t);});}
  @override void didChangeDependencies(){super.didChangeDependencies();if(!_layoutInitialized){_layoutInitialized=true;if(MediaQuery.sizeOf(context).width<_compactWidth)_showPanel=false;}}

  StreamSubscription<String>? _opensSub; StreamSubscription<void>? _answersSub; bool _drainingAnswers=false;

  /// Notification actions: Open shows the messages; an answer (Accept,
  /// Refuse, Read) given from the notification, even application closed,
  /// becomes an acknowledgement queued in the Outbox.
  void _initNotificationActions(){
    _opensSub=_notifications.opens.listen((_){if(mounted)_openMessages();});
    _answersSub=_notifications.answers.listen((_)=>_drainAnswers());
    _notifications.initialize().then((_)=>_drainAnswers());
  }

  Future<void> _drainAnswers() async {
    if(_drainingAnswers)return;
    _drainingAnswers=true;
    try{
      final answers=await takePendingAnswers();
      for(final a in answers){
        final ack=a.toAck();
        await widget.store.cacheAck(ack);
        await _sync.queue(objectId:a.id,objectType:'ack',payload:ack);
        final m=widget.store.messages().map(SarcadeMessage.fromJson).where((x)=>x.id==a.messageId).firstOrNull;
        await _notifications.answered(a.messageId,a.status,key:m==null?null:messageNotificationKey(m));
      }
      if(answers.isNotEmpty&&mounted)setState((){});
    }catch(e){
      debugPrint('SARCADE notification answers not queued yet: $e');
    }finally{
      _drainingAnswers=false;
    }
  }

  /// Messages pressed again (lot 10C): a conversation open comes back to
  /// the list; from the list Messages closes (phone: back to the map).
  final _messagesNav=MessagesNavigator();
  void _openMessages({bool fromButton=false}){
    final shown=_isCompact?_tab==1:_deskId=='messages';
    if(fromButton&&shown&&_messagesNav.backToList())return;
    if(_isCompact){_goTab(fromButton&&shown?0:1);return;}
    if(shown&&!fromButton)return;
    _openDesk('messages',()=>MessagesPage(key:const ValueKey('desk-messages'),api:widget.api,eventId:widget.eventId,
      actorId:widget.deviceId,sync:_sync,store:widget.store,navigator:_messagesNav));
  }
  /// Chat with an operator opened from its sheet (lot 10C, 12 h 54): side
  /// panel, map visible; ✕ or Échap come back to the sheet.
  String? _chatPeer;

  /// Computer: screen shown beside the rail (the rail stays); phone: a
  /// new screen as before.
  Widget? _deskPage; String? _deskId;
  void _openDesk(String id,Widget Function() build){
    if(_drawing.selectMode)_drawing.endSelection();
    if(_isCompact){Navigator.push(context,MaterialPageRoute(builder:(_)=>build()));return;}
    setState((){
      if(_deskId==id){_deskId=null;_deskPage=null;return;}
      _deskId=id;_deskPage=build();_showPanel=false; // one icon in blue (30 Oct 2026, 1 h 21)
    });
  }
  @override void initState(){super.initState();_initNotificationActions();unawaited(requestPersistentStorage());_sync=OfflineSyncService(api:widget.api,store:widget.store,eventId:widget.eventId,onRemoteChange:_onRemoteChange);_initDrawing();_initBearings();_loadLocal();_initRoutes();_initMeasure();_sync.start();_initOperations();_loadBasemaps();_initWebUpdate();unawaited(_loadMyPreferences());_syncUiTimer=Timer.periodic(const Duration(seconds:2),(t){final pw=PowerState.instance;if(!pw.foreground)return;if(t.tick%8==0)_checkOrderArrival();if(t.tick%30==1){unawaited(_loadDevices());unawaited(_tvScreens.refresh(pco:isPco(widget.deviceId)));}if(t.tick%3==0)_drainAnswers();if(shouldPollTvNearby(t.tick,foreground:pw.foreground,pco:true))unawaited(_tvNearby.check(context,widget.eventId));if(mounted&&shouldRefreshUi(t.tick,foreground:pw.foreground,saver:pw.saver))setState((){});});AccessManager.instance.addListener(_onAccessChanged);_start();unawaited(_loadRoles());}

  /// Rights given by the server for the checked email (PCO, administrator).
  Future<void> _loadRoles() async {
    myActorId=widget.deviceId;
    // Link pill of every screen: a touch opens the Diagnostic (31 Oct 2026).
    linkStatusOnTap=()=>_openDiagnostics();
    try{
      final me=await widget.api.me();
      myRoles={for(final r in (me?['roles'] as List?)??const [])'$r'};
      if(mounted)setState((){});
    }catch(e){
      debugPrint('SARCADE rights not read: $e');
    }
  }
  bool _validPosition(SarcadePosition p){
    final t=p.time.toUtc(), now=DateTime.now().toUtc();
    return t.isAfter(DateTime.utc(2020)) && t.isBefore(now.add(const Duration(days:1)));
  }
  void _loadLocal(){for(final j in widget.store.positions()){final p=SarcadePosition.fromJson(j);if(p.eventId==widget.eventId&&_validPosition(p))_positions[p.deviceId]=p;}for(final j in widget.store.pois()){final p=SarcadePoi.fromJson(j);if(p.eventId==widget.eventId&&!p.deleted)_pois[p.id]=p;}for(final j in widget.store.references()){final p=ReferenceSite.fromJson(j);if(p.status=='active')_references[p.id]=p;}}
  Future<void> _start() async {
    if(_starting)return; _starting=true;
    try {
      final data=await Future.wait([widget.api.latestPositions(widget.eventId),widget.api.pois(widget.eventId)]);
      _mergePositions(data[0] as List<SarcadePosition>);
      final serverPois=data[1] as List<SarcadePoi>;
      // Points deleted elsewhere while closed leave the map (pending ones stay).
      _pois.removeWhere((id,_)=>!_sync.isPending(id)&&!serverPois.any((p)=>p.id==id));
      for(final p in serverPois){_pois[p.id]=p;}
      // Safety net: positions only come by the realtime channel; read the
      // latest ones again every minute in case some were missed.
      _positionsTimer?.cancel();
      _positionsTimer=Timer.periodic(const Duration(seconds:60),(_){if(PowerState.instance.foreground)unawaited(_reloadPositions());});
      try{await _refreshReferences(silent:true);}catch(_){}
      _realtime.connect(widget.api.websocketUri(widget.eventId),headers:widget.api.realtimeHeaders);
      await _rtSub?.cancel();
      _rtSub=_realtime.events.listen(_onRealtime);
      registerWakeupHook=_wakeupNoted;
      unawaited(_wakeupNoted());
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
    Tooltip.dismissAllToolTips();
    // Each opening of the tools starts from the profile colour.
    // Closing the bar ends any selection: the map is never left blocked
    // (bug of 30 Oct 2026, 17 h 35).
    if(_drawingTools){_drawing.selectTool(null);_drawing.endSelection();}else{
      _drawing.color=_profileDrawColor;
      _bearings.operatorColor=_profileDrawColor;
      // Drawing with the drawings hidden shows nothing (28 Oct 2026): shown again.
      if(!_showDrawings)unawaited(_setShown('show_draw',true));
    }
    setState(()=>_drawingTools=!_drawingTools);
  }
  /// Problems all lead to the Diagnostic, over the map (30 Oct 2026, 12 h 47).
  void _openDiagnostics({bool failedAgain=false}){
    // As the former links sheet: started without network, start now; real
    // time down, reconnect.
    if(_sync.lastSyncOk&&!_sync.eventUnknown){if(!_started){unawaited(_start());}else if(!_realtime.connected){_realtime.reconnectNow();}}
    showDiagnosticsSheet(context,api:widget.api,server:widget.api.baseUrl,eventId:widget.eventId,
    actorId:widget.deviceId,failedAgain:failedAgain,onSignIn:_signIn).then((_){if(mounted)setState((){});});
  }
  /// « Envoyer » of the banner = « Tout réessayer »; failing again opens the
  /// list with Supprimer and Exporter (unsent_summary.dart).
  Future<void> _retryAllUnsent() async {final left=await _sync.retryAll();if(!mounted)return;setState((){});if(left.isNotEmpty)_openDiagnostics(failedAgain:true);}
  // --- Devices: platform, version, last contact (« Version de l'application
  // et connexions des opérateurs », 29 Oct 2026) ---
  final Map<String,Map<String,dynamic>> _devices={};
  Future<void> _loadDevices() async {
    try{
      final list=await widget.api.devices(widget.eventId);
      if(!mounted)return;
      setState((){for(final d in list){_devices['${d['device_id']}']=d;}});
    }catch(_){/* offline: the last list stays */}
    unawaited(_loadFixedClasses());
  }
  /// « SARCADE 0.1.0+415 · Android · dernier contact il y a 12 s ».
  String? _deviceLine(String deviceId){
    final d=_devices[deviceId]; if(d==null)return null;
    final seen=DateTime.tryParse('${d['last_seen']??d['last_contact_at']??''}');
    return [
      if('${d['app_version']??''}'.isNotEmpty)'SARCADE ${d['app_version']}',
      if('${d['platform']??''}'.isNotEmpty)platformLabel('${d['platform']}'),
      if(seen!=null)S.t('device.lastContact',{'age':ageLabel(seen.toUtc(),DateTime.now().toUtc())}),
    ].join(' · ');
  }

  void _onRealtime(RealtimeEvent e){
    if(e.type=='aprs.class.updated'){unawaited(_applyFixedClass(e.data));}
    if(e.type=='device.updated'){final id='${e.data['device_id']??''}';if(id.isNotEmpty&&mounted)setState(()=>_devices[id]=Map<String,dynamic>.from(e.data));}
    if(e.type==RealtimeService.reconnectedType){unawaited(_reloadPositions());return;}
    if(e.type=='position.updated'){final p=SarcadePosition.fromJson(e.data);if(_validPosition(p)){widget.store.cachePosition(p.toJson());_traces.add(p);if(mounted)setState((){_positions[p.deviceId]=p;if(_selectedDevice==p.deviceId)_trace.add(p);});}}
    if(e.type=='poi.created'||e.type=='poi.updated'||e.type=='poi.deleted'){unawaited(applyRemotePoi(_pois,widget.store,Map<String,dynamic>.from(e.data),widget.eventId).then((c){if(c&&mounted)setState((){});}));}
    if(e.type=='message.created'){_receiveMessage(e.data);}
    if(e.type=='message.deleted'){unawaited(widget.store.cacheMessage(Map<String,dynamic>.from(e.data)));}
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
    if(m.deleted){if(mounted)setState((){});return;}
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
        await _notifications.message(title:'SARCADE · ${S.t(priorityKey(m.priority))} · ${m.senderId}',body:m.body,priority:m.priority,
          payload:NotificationPayload(eventId:widget.eventId,messageId:m.id,deviceId:widget.deviceId,priority:m.priority,tag:messageNotificationKey(m)));
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
    preferOffline:_preferOffline,layers:_layerSections,
    onChoose:(id) async {await widget.store.setPreference('basemap:${widget.eventId}',id);if(mounted)setState((){});},
    onPreferOffline:(v) async {await widget.store.setPreference('basemap_offline',v?'1':null);if(mounted)setState((){});});

  void _openWeather({({double lat,double lon,String label})? point}){
    final mine=_positions[widget.deviceId];
    _openDesk('weather',()=>WeatherPage(key:ValueKey('desk-weather-${point?.label}'),api:widget.api,store:widget.store,eventId:widget.eventId,
      actorId:widget.deviceId,lowBandwidth:_ops.settings.lowBandwidth,point:point,
      fallback:mine==null?null:(lat:mine.lat,lon:mine.lon)));
  }

  /// Long press on the map (click on a computer): grid menu of the point
  /// (point_menu.dart); on or within ≈ 30 m of my position, a bearing from
  /// the GPS position (decision of 30 Oct 2026, 3 h 05).
  Future<void> _onLongPress(LatLng point,{bool gesture=false}) async {
    if(_adjusting!=null){_adjustOrigin(point);return;}
    final wide=MediaQuery.sizeOf(context).width>=_compactWidth;
    final me=_me??_positionOf(widget.deviceId);
    if(gesture&&_adrasec&&nearOwnPosition(point,me)){await _bearings.startTaking();if(!mounted)return;if(wide){_startAim(BearingAim(me!));}else{_focusBearing(me!);}return;}
    // Long press on a line, a point, a text or the outline of a shape:
    // « Sélectionner » it. Inside a shape the point menu opens, the shape
    // offered at its top (card « Appui long dans une zone dessinée », 31 Oct
    // 2026: a bearing could not be taken inside a sector any more).
    var under=const <MapFeature>[];
    if(gesture&&_showDrawings){
      final cam=_map.camera; final at=cam.latLngToScreenOffset(point);
      final hit=hitOutline(_drawing.features,at,cam.latLngToScreenOffset,radiusPx:_circleRadiusPx);
      if(hit!=null&&_drawing.canSelect(hit)){_drawing.startSelection(hit.id);return;}
      under=shapesUnder(_drawing.features,at,cam.latLngToScreenOffset,radiusPx:_circleRadiusPx).where(_drawing.canSelect).toList();
    }
    // Shown in the language of each device wherever it is displayed
    // (pointLabel, 31 Oct 2026).
    final label=S.t('nav.point');
    final choice=await showPointMenu(context,point:point,places:_places,pco:isPco(widget.deviceId),adrasec:_adrasec,
      coordinates:formatCoordinates(point,_coordFormat,mgrsDigits:_mgrsDigits),
      objects:[for(final f in under)(id:f.id,label:f.label.trim().isEmpty?f.kind.label:f.label.trim())],
      onSelectObject:_drawing.startSelection);
    if(choice==null||!mounted)return;
    switch(choice){
      case PointAction.bearing: await _bearings.startTaking(from:point);if(!mounted)return;if(wide){_startAim(BearingAim(point));}else{_focusBearing(point);}
      case PointAction.poi: await _createPoiHere(point);
      case PointAction.order: await _sendOperatorHere(point);
      case PointAction.measure: await _measureTo(point,label);
      case PointAction.navigate: await _navigateTo(point,label);
      case PointAction.route: await _routeToHere(point);
      case PointAction.external: await _openElsewhere(point,label);
      case PointAction.select: if(!_showDrawings)await _setShown('show_draw',true);_drawing.startSelection();
      case PointAction.weather: _openWeather(point:(lat:point.latitude,lon:point.longitude,label:label));
      case PointAction.info: await openPointInfo(context,point:point,places:_places,from:me,onSendMessage:_sendText);
    }
  }

  // --- Move orders (PCO → operator, 29 Oct 2026) ------------------------------

  List<MoveOrder> get _moveOrders=>_routes.moveOrders.map(MoveOrder.new).toList();
  /// The open order addressed to this device, the most recent first.
  MoveOrder? get _myOrder{
    final mine=_moveOrders.where((o)=>o.targetId==widget.deviceId&&o.open).toList()
      ..sort((a,b)=>'${b.json['updated_at']}'.compareTo('${a.json['updated_at']}'));
    return mine.isEmpty?null:mine.first;
  }
  LatLng? _positionOf(String id){final p=_positions[id];return p==null?null:LatLng(p.lat,p.lon);}

  Future<void> _sendOperatorHere(LatLng point) async {
    final now=DateTime.now().toUtc();
    final ops=[for(final p in _positions.values)
      if(p.source!='aprs'&&p.deviceId!=widget.deviceId)(id:p.deviceId,label:p.label,age:ageLabel(p.time.toUtc(),now))]
      ..sort((a,b)=>a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final d=await showMoveOrderDialog(context,ops);
    if(d==null||!mounted)return;
    // No default name stored: each device shows its own (31 Oct 2026).
    final label=d.label.trim();
    for(final t in d.targets){await _routes.sendMoveOrder(targetId:t,destination:point,label:label,note:d.note);}
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('order.sent',{'n':d.targets.length}))));
  }

  void _showMoveOrder(MoveOrder o){
    showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:Icon(Icons.flag,color:moveOrderColor(o.status)),title:Text('${S.t('order.title')} · ${o.targetId}'),
        subtitle:Text('« ${o.label} » · ${S.t('order.status.${o.status}')}${o.note.isEmpty?'':'\n${o.note}'}')),
      // « Ouvrir dans… » Waze, Google Maps… (31 Oct 2026).
      ListTile(key:const ValueKey('order-open-in'),leading:const Icon(Icons.open_in_new),title:Text(S.t('ext.open')),
        onTap:(){Navigator.pop(c);unawaited(_openElsewhere(o.destination,o.label));}),
      if(o.open&&(isPco(widget.deviceId)||o.createdBy==widget.deviceId))ListTile(leading:const Icon(Icons.cancel_outlined),
        title:Text(S.t('order.cancel')),onTap:(){Navigator.pop(c);unawaited(_routes.setMoveOrderStatus(o.json,'cancelled'));}),
      if(canRemoveMoveOrder(o,widget.deviceId,pco:isPco(widget.deviceId)))ListTile(key:const ValueKey('order-remove'),leading:const Icon(Icons.wrong_location_outlined),
        title:Text(S.t('order.remove')),onTap:(){Navigator.pop(c);unawaited(_routes.removeMoveOrder(o.json));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('order.removed'))));}),
    ])));
  }

  /// « Arrivé » on its own within 50 m of the destination of an accepted order.
  void _checkOrderArrival(){
    final o=_myOrder; final me=_me??_positionOf(widget.deviceId);
    if(o!=null&&me!=null&&moveOrderReached(o,me))unawaited(_routes.setMoveOrderStatus(o.json,'arrived'));
  }

  Widget? _orderBanner(){
    final o=_myOrder;
    if(o==null)return null;
    return ConstrainedBox(constraints:const BoxConstraints(maxWidth:460),child:MoveOrderBanner(order:o,
      onAccept:() async {await _routes.setMoveOrderStatus(o.json,'accepted');if(mounted)await _navigateTo(o.destination,o.label);},
      onRefuse:()=>unawaited(_routes.setMoveOrderStatus(o.json,'refused')),
      onNavigate:()=>unawaited(_navigateTo(o.destination,o.label)),
      onArrived:()=>unawaited(_routes.setMoveOrderStatus(o.json,'arrived'))));
  }

  /// « Itinéraire jusqu'ici » in one gesture: a route from my position to
  /// the point, legs on the paths, opened in the routes panel.
  Future<void> _routeToHere(LatLng point) async {
    final me=_positions[widget.deviceId];
    final from=me==null?_mapCentre():LatLng(me.lat,me.lon);
    if(from==null)return;
    final r=await _routes.createRoute(name:S.t('routes.toHereName',{'time':'${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}'}),profile:'foot',legMode:'paths');
    await _routes.addWaypoint(r,from);
    await _routes.addWaypoint(_routes.route(r.id)??r,point);
    if(!mounted)return;
    setState((){_showRoutesPanel=true;_showPanel=false;_showReferencePanel=false;_selectedRouteId=r.id;});
    _fitPoints([from,point]);
  }

  void _initMeasure(){
    _measure=MeasureController(location:_location);
    // Manual declination: setting of this device, kept offline.
    _measure.declinationOverride=parseDeclination(widget.store.preference('declination_manual')??'');
    _measure.addListener(_onRoutesChanged);
  }

  Future<void> _editDeclination() async {
    final fr=S.lang=='fr';
    String decl(double d)=>formatDeclination(d,decimal:fr?',':'.',west:fr?'O':'W');
    final ctrl=TextEditingController(text:_measure.declinationOverride==null?'':decl(_measure.declinationOverride!));
    var manual=_measure.manualDeclination;
    String? error;
    final result=await showDialog<String>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('measure.decl.title')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(S.t('measure.decl.wmm',{'v':decl(_measure.wmmDeclination)})),
        if(MeasureController.wmmExpired())Text(S.t('measure.wmmExpired'),style:TextStyle(color:Theme.of(c).colorScheme.error)),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(S.t('measure.decl.manual')),value:manual,onChanged:(v)=>set(()=>manual=v)),
        if(manual)TextField(controller:ctrl,autofocus:true,decoration:InputDecoration(hintText:S.t('measure.decl.hint'),errorText:error)),
        const SizedBox(height:8),
        Text(S.t('measure.decl.help'),style:Theme.of(c).textTheme.bodySmall),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:(){
          if(!manual){Navigator.pop(c,'');return;}
          final v=parseDeclination(ctrl.text);
          if(v==null){set(()=>error=S.t('measure.decl.invalid'));return;}
          Navigator.pop(c,v.toString());
        },child:Text(S.t('common.save'))),
      ],
    )));
    ctrl.dispose();
    if(result==null)return;
    await widget.store.setPreference('declination_manual',result.isEmpty?null:result);
    _measure.declinationOverride=result.isEmpty?null:double.parse(result);
    if(mounted)setState((){});
  }

  Future<void> _measureTo(LatLng point,String label) async {
    if(!_showBearings)unawaited(_setShown('show_brg',true));
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
    if(t!=null)await _createPoiHere(t);
  }

  /// « Créer un point d'intérêt ici » (grid and measure): name and icon.
  Future<void> _createPoiHere(LatLng t) async {
    final d=await showCreatePoiDialog(context,color:Color(poiColorFor(_profileDrawColor)));
    if(d==null||!mounted)return;
    final poi=newPoiJson(id:_uuid.v4(),eventId:widget.eventId,at:t,label:d.name,actor:widget.deviceId,drawColor:_profileDrawColor,icon:d.icon);
    await widget.store.cachePoi(poi);
    setState(()=>_pois[poi['id'] as String]=SarcadePoi.fromJson(poi));
    await _sync.queue(objectId:poi['id'] as String,objectType:'poi',payload:poi);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('poi.created'))));
  }

  // --- Distress (ATAK 4) and résection (ATAK 2) ---
  bool get _inDistress=>widget.store.preference('distress:${widget.eventId}')=='1';

  /// SOS of other operators not closed yet, with « Couper le son » (sos_alert.dart).
  Widget? _sosAlert(){
    final open=openDistress(widget.store.messages().map(SarcadeMessage.fromJson).where((m)=>m.eventId==widget.eventId),widget.deviceId).values.toList();
    if(open.isEmpty)return null;
    final key='sosMuted:${widget.eventId}';
    return SosAlertBanner(open:open,muted:sosMuted(open,widget.store.preference(key)),onOpen:_openMessages,onMute:() async {
      for(final m in open){await _notifications.answered(m.id,'read',key:messageNotificationKey(m));}
      await widget.store.setPreference(key,sosMuteKey(open));
      if(mounted)setState((){});
    });
  }

  /// Immediate message to everyone with the position: every device is
  /// woken; kept until the operator ends it explicitly.
  Future<void> _sendQuick(String body,{String priority='immediate'}) async {
    final m=SarcadeMessage(id:const Uuid().v4(),eventId:widget.eventId,senderId:widget.deviceId,recipientIds:const [],
      priority:priority,body:body,createdAt:DateTime.now().toUtc());
    await widget.store.cacheMessage(m.toJson());
    await _sync.queue(objectId:m.id,objectType:'message',payload:m.toJson());
  }

  String _myPositionText(){
    final p=_positions[widget.deviceId];
    return p==null?S.t('distress.noPosition'):'${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';
  }

  late final PlaceDescriber _places=PlaceDescriber(widget.api);
  Future<void> _sendDistress() async {
    final p=_positions[widget.deviceId];
    final where=await _places.distressSuffix(p==null?null:LatLng(p.lat,p.lon)); // empty after 1.5 s without answer
    await _sendQuick(S.t('distress.body',{'who':widget.deviceId,'pos':_myPositionText()})+where);
    await widget.store.setPreference('distress:${widget.eventId}','1');
    if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('distress.sent'))));}
  }

  Future<void> _distress() async {
    if(_inDistress){
      final end=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('distress.endTitle')),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
          FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('distress.end')))]));
      if(end!=true)return;
      await _sendQuick(S.t('distress.endBody',{'who':widget.deviceId}),priority:'urgent');
      await widget.store.setPreference('distress:${widget.eventId}',null);
      if(mounted)setState((){});
      return;
    }
    // Held button: no distress sent by a stray touch.
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('distress.title')),content:Text(S.t('distress.help')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        _HoldButton(label:S.t('distress.hold'),onDone:()=>Navigator.pop(c,true)),
      ]));
    if(ok!=true)return;
    await _sendDistress();
  }

  /// Résection (menu Outils): panel beside the map.
  void _openResection(){
    final me=_positions[widget.deviceId];
    _resectionCtl.around=me!=null?LatLng(me.lat,me.lon):_mapCentre();
    setState((){_tab=0;_deskPage=null;_deskId=null;_showResection=true;_showPanel=false;_showReferencePanel=false;_showRoutesPanel=false;_drawingRouteId=null;});
  }

  void _resectionPick(int i){
    _resectionCtl.pick(i);
    _startPick(S.t('resection.pickHint',{'n':'${i+1}'}),(p,site){
      _resectionCtl.setKnown(i,KnownPoint(point:p,label:site?.name??formatCoordinates(p,_coordFormat,mgrsDigits:_mgrsDigits),site:site));
    });
  }

  /// Sheet of a waypoint touched on the map (or the line of its route).
  Future<void> _openWaypoint(Waypoint w) async {
    final r=_routes.route(w.routeId);
    if(r==null)return;
    final a=await showWaypointSheet(context,r,w,actor:widget.deviceId);
    if(a==null||!mounted)return;
    switch(a){
      case WaypointAction.edit: await editWaypointDialog(context,_routes,w);
      case WaypointAction.move: _startPick(S.t('routes.moveHint'),(p,_)=>unawaited(_routes.updateWaypoint(w,{'lat':p.latitude,'lon':p.longitude})));
      case WaypointAction.delete: await _routes.deleteWaypoint(w);
      case WaypointAction.open: setState((){_tab=0;_deskPage=null;_deskId=null;_showRoutesPanel=true;_showPanel=false;_showReferencePanel=false;_selectedRouteId=r.id;});
    }
  }

  /// List of the points (screen on the phone, panel on a computer).
  void _openPoiList(){
    Widget list(VoidCallback? close)=>PoiListView(pois:_pois.values.toList(),from:_me??_positionOf(widget.deviceId)??_mapCentre(),onClose:close,
      onOpen:(p){if(_isCompact)Navigator.pop(context);_onMapNow((){_fitPoints([LatLng(p.lat,p.lon)]);unawaited(_openPoi(p));});});
    if(_isCompact){Navigator.push(context,MaterialPageRoute(builder:(c)=>Scaffold(appBar:LinkedAppBar(title:Text(S.t('poi.layer'))),body:list(null))));return;}
    _openDesk('pois',()=>Material(child:list(()=>setState((){_deskId=null;_deskPage=null;}))));
  }

  /// Sheet of a point of interest (touch on the pin or in the layers list).
  Future<void> _openPoi(SarcadePoi p) async {
    final can=canEditPoi(p,widget.deviceId);
    final a=await showPoiSheet(context,p,format:_coordFormat,mgrsDigits:_mgrsDigits,canEdit:can);
    if(a==null||!mounted)return;
    if(a=='route'){await _routeToHere(LatLng(p.lat,p.lon));return;}
    if(a=='send'){await Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,
      actorId:widget.deviceId,sync:_sync,store:widget.store,initialText:poiMessage(p,_coordFormat,mgrsDigits:_mgrsDigits))));return;}
    if(a=='icon'){final k=await showPoiIconPicker(context,current:p.icon??'pin',color:Color(poiColor(p)));
      if(k!=null&&mounted){await changePoiIcon(_pois,widget.store,_sync,p,k,widget.deviceId);if(mounted)setState((){});}return;}
    if(a=='rename'){final n=await askPoiName(context,p);if(n!=null&&mounted){await renamePoi(_pois,widget.store,_sync,p,n,widget.deviceId);if(mounted)setState((){});}return;}
    if(a=='delete'&&await confirmPoiDelete(context,p)){
      await deletePoi(_pois,widget.store,_sync,p,widget.deviceId);
      if(mounted){setState((){});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('poi.deleted'))));}
    }
  }

  /// A designated point of the event (same as « Enregistrer le point »).
  Future<void> _saveDesignated(LatLng t,String label) async {
    final poi=newPoiJson(id:_uuid.v4(),eventId:widget.eventId,at:t,label:label,actor:widget.deviceId,drawColor:_profileDrawColor);
    await widget.store.cachePoi(poi);
    setState(()=>_pois[poi['id'] as String]=SarcadePoi.fromJson(poi));
    await _sync.queue(objectId:poi['id'] as String,objectType:'poi',payload:poi);
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('measure.poiSaved'))));
  }

  Widget _resectionPanel(double width)=>SizedBox(width:width,child:ResectionPanel(controller:_resectionCtl,
    sites:_references.values.where((r)=>r.isHighPoint||r.isRelay).toList(),
    canCompass:_phoneOrTablet,
    onClose:()=>setState((){_showResection=false;_resectionCtl.result=null;}),
    onPickOnMap:_resectionPick,
    onFocus:(p)=>_map.move(p,14),
    onCreatePoint:(p)=>_saveDesignated(p,S.t('resection.pointLabel',{'t':hhmm(DateTime.now())})),
    onSendPosition:(p)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,
      actorId:widget.deviceId,sync:_sync,store:widget.store,
      initialText:S.t('resection.message',{'pos':formatCoordinates(p,_coordFormat,mgrsDigits:_mgrsDigits),'r':geo.formatDistance(_resectionCtl.result?.radiusM??0)})))),
    onCopy:(p){Clipboard.setData(ClipboardData(text:formatCoordinates(p,_coordFormat,mgrsDigits:_mgrsDigits)));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('common.copied'))));},
  ));

  /// Sights and result of the résection on the map.
  List<Widget> _resectionLayers(){
    if(!_showResection)return const [];
    final c=_resectionCtl; final res=c.result;
    final known=[for(var i=0;i<3;i++)if(c.sights[i].known!=null)(i,c.sights[i].known!.point)];
    return [
      PolylineLayer(polylines:[for(final (a,b) in resectionLines(c))Polyline(points:[a,b],strokeWidth:2.5,color:Colors.indigo.withValues(alpha:0.85))]),
      if(res?.centre!=null)CircleLayer(circles:[CircleMarker(point:res!.centre!,radius:res.radiusM,useRadiusInMeter:true,
        color:const Color(0x333F51B5),borderColor:Colors.indigo,borderStrokeWidth:2)]),
      MarkerLayer(markers:[
        for(final (i,p) in known)Marker(point:p,width:26,height:26,child:Container(alignment:Alignment.center,
          decoration:BoxDecoration(color:Colors.indigo,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:2)),
          child:Text('${i+1}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:12)))),
        if(res?.centre!=null)Marker(point:res!.centre!,width:28,height:28,child:const Icon(Icons.my_location,color:Colors.indigo,size:28)),
      ]),
    ];
  }

  /// Menu « Outils »: tiles of the tools used less often.
  /// Itinéraires panel beside the map (from « Outils » on a computer, 29 Oct 2026).
  void _openRoutesPanel()=>setState((){_tab=0;_deskPage=null;_deskId=null;_showRoutesPanel=true;_showPanel=false;_showReferencePanel=false;_showResection=false;});

  /// « Outils »: Itinéraires first; « Mesure » removed, the measure starts
  /// from the point menu (30 Oct 2026, 1 h 48). Phone: the « Outils » tab.
  List<ToolItem> _toolItems()=>[
    // Ordered by use (card « Outils, ordre par usage », 30 Oct 2026, 12 h 50).
    ToolItem(id:'weather',icon:Icons.cloud_outlined,title:S.t('weather.menu'),subtitle:S.t('tools.weatherHelp'),color:Colors.orange,onTap:()=>_openWeather()),
    ToolItem(id:'converter',icon:Icons.pin_drop_outlined,title:S.t('converter.title'),subtitle:S.t('tools.converterHelp'),color:Colors.blue,
      onTap:()=>_openConverter()),
    ToolItem(id:'routes',icon:Icons.route,title:S.t('routes.menu'),subtitle:S.t('tools.routesHelp'),color:Colors.green,onTap:_openRoutesPanel),
    if(_adrasec)ToolItem(id:'resection',icon:Icons.my_location,title:S.t('resection.title'),subtitle:S.t('tools.resectionHelp'),color:Colors.indigo,onTap:_openResection),
    ToolItem(id:'tv',icon:Icons.tv,title:S.t('tv.menu'),subtitle:S.t('tools.tvHelp'),color:Colors.deepPurple,group:ToolGroup.pc,
      onTap:_openTvScreens),
    if(_adrasec&&isPco(widget.deviceId))ToolItem(id:'aprs',icon:Icons.settings_input_antenna,title:S.t('aprs.title'),subtitle:S.t('tools.aprsHelp'),color:Colors.purple,group:ToolGroup.pc,
      onTap:()=>_openDesk('aprs',()=>AprsPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId,
        onShowOnMap:(p,_)=>_onMapNow((){setState(()=>_searchPin=p);_map.move(p,15);})))),
  ];
  /// Convertisseur étoffé (lot 5): actions handed back to the map.
  void _openConverter({LatLng? initial})=>_openDesk('converter',()=>CoordinateConverterPage(key:ValueKey('desk-converter-$initial'),initial:initial,
    location:_location,store:widget.store,items:_searchables,addresses:_searchAddresses,tileUrl:_tileUrl,
    actions:ConverterActions(
      show:(p)=>_onMapNow((){setState(()=>_searchPin=p);_map.move(p,15);}),
      measure:(p)=>_onMapNow(()=>_measureTo(p,S.t('nav.point'))),
      poi:(p)=>_onMapNow(()=>_createPoiHere(p)),
      bearing:_adrasec?(p)=>_onMapNow(() async {await _bearings.startTaking(from:p);if(mounted)_focusBearing(p);}):null,
      order:isPco(widget.deviceId)?((p)=>_onMapNow(()=>_sendOperatorHere(p))):null,
      message:_sendText,
      pickOnMap:()=>_startPick(S.t('converter.touchMap'),(p,_)=>_openConverter(initial:p)))));
  void _openTools(){if(_isCompact){_goTab(3);return;}_openDesk('tools',()=>ToolsPage(key:const ValueKey('desk-tools'),items:_toolItems()));}

  /// A tool acting on the map: back to the map (tab, desk closed) first.
  void _onMapNow(VoidCallback f){setState((){_tab=0;_deskPage=null;_deskId=null;});f();}

  /// A text ready in Messages (fiche « Infos du point », convertisseur).
  void _sendText(String text)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,
    actorId:widget.deviceId,sync:_sync,store:widget.store,initialText:text)));
  void _sendMeasure()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,
    actorId:widget.deviceId,sync:_sync,store:widget.store,initialText:measureMessage(_measure,_coordFormat,mgrsDigits:_mgrsDigits))));

  /// « Open in… » with the navigation app chosen by the organisation.
  Future<void> _openElsewhere(LatLng p,String label)=>openInOtherApp(context,p,pointLabel(label),
    app:widget.store.preference('nav_app')??'operator',hideTracking:widget.store.preference('nav_hide_tracking')=='1',
    readPref:widget.store.preference,writePref:widget.store.setPreference);

  void _initRoutes(){
    _routes=RoutesController(api:widget.api,store:widget.store,sync:_sync,eventId:widget.eventId,actorId:widget.deviceId);
    _graphs=RoadGraphService(api:widget.api,store:widget.store);
    _graphs.addListener(_onRoutesChanged);
    _graphs.start();
    _nav=NavigationController(api:widget.api,routes:_routes,location:_location,eventId:widget.eventId,graphs:_graphs);
    _routes.addListener(_onRoutesChanged);
    _nav.addListener(_onNavigationChanged);
    _routes.refresh();
  }
  void _onRoutesChanged(){if(mounted)setState((){});}

  // --- Follow mode and variants of the navigation (decisions of 10 Oct 2026) ---
  bool _follow=false, _followPending=false; LatLng? _navStart, _lastFollowCenter; double? _lastFollowRotation;
  final LayerHitNotifier<int> _variantHits=ValueNotifier(null);
  final LayerHitNotifier<Bearing> _bearingHits=ValueNotifier(null);

  static bool get _phoneOrTablet=>!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS);
  /// Phones and tablets turn the map; computers keep north up unless chosen.
  bool get _followRotates=>_phoneOrTablet||widget.store.preference('nav_rotate_desktop')=='1';

  void _onNavigationChanged(){
    if(_nav.state!=NavState.active){
      if(_follow||_followPending)_setFollow(false);
    }else{
      final p=_nav.position, start=_navStart;
      if(_followPending&&p!=null&&start!=null&&distanceM(start,p)>=followEngageDistanceM)_setFollow(true);
      if(_follow)_applyFollow();
    }
    _onRoutesChanged();
  }

  void _setFollow(bool on){
    _follow=on; _followPending=false;
    _lastFollowCenter=null; _lastFollowRotation=null;
    if(on){
      // Drawing is off while following: drawn shapes assume north up.
      _drawing.selectTool(null); _drawingTools=false;
      if(_phoneOrTablet)_nav.startCompass();
      _applyFollow();
    }else{
      _nav.stopCompass();
      try{_map.rotate(0);}catch(_){/* map not ready */}
    }
    if(mounted)setState((){});
  }

  void _applyFollow(){
    final p=_nav.position;
    if(p==null)return;
    final heading=followHeading(course:_nav.course,speedMs:_nav.speedMs,compassTrue:_nav.compassTrue,rotate:_followRotates);
    final rotation=mapRotationFor(heading);
    if(!followNeedsUpdate(lastCenter:_lastFollowCenter,lastRotation:_lastFollowRotation,center:p,rotation:rotation))return;
    _lastFollowCenter=p; _lastFollowRotation=rotation;
    try{
      final zoom=_map.camera.zoom<followMinZoom?followMinZoom:_map.camera.zoom;
      _map.moveAndRotate(p,zoom,rotation);
    }catch(_){/* map not ready */}
  }

  /// A gesture of the operator on the map leaves the follow mode.
  void _onMapEvent(MapEvent e){
    const gestures={MapEventSource.dragStart,MapEventSource.onDrag,MapEventSource.multiFingerGestureStart,
      MapEventSource.onMultiFinger,MapEventSource.doubleTap,MapEventSource.doubleTapHold,MapEventSource.scrollWheel,
      MapEventSource.keyboard,MapEventSource.cursorKeyboardRotation};
    if((_follow||_followPending)&&gestures.contains(e.source))_setFollow(false);
  }

  List<Widget> _variantLayers(){
    final alts=_nav.state==NavState.active?_nav.alternatives:const <Itinerary>[];
    if(alts.isEmpty)return const [];
    return [MouseRegion(hitTestBehavior:HitTestBehavior.deferToChild,cursor:SystemMouseCursors.click,child:GestureDetector(
      onTap:(){
        final hit=_variantHits.value;
        if(hit!=null&&hit.hitValues.isNotEmpty){_nav.chooseAlternative(hit.hitValues.first);if(_phoneOrTablet)_setFollow(true);}
      },
      child:PolylineLayer<int>(hitNotifier:_variantHits,polylines:[
        for(var i=0;i<alts.length;i++)Polyline<int>(points:alts[i].geometry,strokeWidth:6,color:Colors.blueGrey.withValues(alpha:0.75),
          borderStrokeWidth:1.5,borderColor:Colors.white,hitValue:i),
      ]),
    ))];
  }

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
    // A graph published since the event opened is fetched now (Wi-Fi).
    if(_graphs.graph==null)unawaited(_graphs.check());
    final mode=await chooseNavigationMode(context,label);
    if(mode==null)return;
    if(_follow)_setFollow(false);
    await _nav.start(point,label,mode);
    final it=_nav.itinerary;
    _navStart=_nav.position;
    if(it!=null&&it.geometry.length>1)_fitPoints([...it.geometry,for(final a in _nav.alternatives)...a.geometry]);
    // Phones and tablets follow at once, or once the operator moves off when
    // variants are shown to choose from.
    if(_phoneOrTablet&&_nav.state==NavState.active){
      if(_nav.alternatives.isEmpty){_setFollow(true);}else{setState(()=>_followPending=true);}
    }
  }

  Future<void> _finishClosure() async {
    if(_closureDraft.length<2){setState((){_drawingClosure=false;_closureDraft.clear();});return;}
    final label=await askClosureLabel(context);
    if(label!=null&&label.trim().isNotEmpty)await _routes.createClosure(label.trim(),List<LatLng>.from(_closureDraft));
    if(mounted)setState((){_drawingClosure=false;_closureDraft.clear();});
  }

  /// Web client: checks every 5 minutes (and 20 s after start) whether the
  /// server publishes a newer build than the one running.
  Timer? _webUpdateTimer; bool _webUpdate=false; String? _servedVersion, _servedBuild;
  static const _expectedVersionKey='web_update_expected';
  void _initWebUpdate(){
    if(!isWebPlatform||appBuild.isEmpty)return;
    // After « Mettre à jour »: « Version 0.1.0+560 chargée » once.
    final expected=widget.store.preference(_expectedVersionKey);
    if(expected!=null){
      unawaited(widget.store.setPreference(_expectedVersionKey,null));
      WidgetsBinding.instance.addPostFrameCallback((_){
        if(!mounted)return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(S.t(expected==appVersionFull||expected==appBuild?'webUpdate.loaded':'webUpdate.notLoaded',{'v':appVersionFull,'e':expected}))));
      });
    }
    Future<void> check() async {
      final served=await fetchServedBuild();
      final available=webUpdateAvailable(appBuild,served.build);
      if(mounted&&(available!=_webUpdate||served.version!=_servedVersion))setState((){_webUpdate=available;_servedVersion=served.version;_servedBuild=served.build;});
    }
    Timer(const Duration(seconds:20),check);
    _webUpdateTimer=Timer.periodic(const Duration(minutes:5),(_)=>check());
  }

  /// Web client: « Activer les notifications » until the operator answers
  /// (or chooses « Plus tard » for this session).
  bool _notificationsDismissed=false;
  bool get _notificationsBanner=>!_notificationsDismissed&&_notifications.needsUserAction;
  Future<void> _enableNotifications() async {
    final ok=await _notifications.requestFromUser();
    if(!mounted)return;
    setState((){});
    if(ok)unawaited(_registerWakeup());
    if(!ok)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('notifications.refused'))));
  }

  /// Wake-up when SARCADE is closed (note « Réveil des appareils »): the
  /// Web Push subscription of this browser is given to the server. Android
  /// (Firebase) comes with its own step.
  Future<bool> _registerWakeup() async {
    if(fcmAvailable){
      try{
        final token=await fcmToken();
        if(token==null)return false;
        await widget.api.registerWakeToken(widget.eventId,widget.deviceId,fcmPlatform,token);
        _fcmRefresh??=fcmTokenRefresh().listen((t)=>unawaited(widget.api.registerWakeToken(widget.eventId,widget.deviceId,fcmPlatform,t).catchError((_){})));
        _fcmForeground??=fcmForeground().listen((_)=>unawaited(_sync.syncNow()));
        return true;
      }catch(e){
        debugPrint('SARCADE wake-up not registered: $e');
        return false;
      }
    }
    if(!isWebPlatform)return false;
    try{
      final config=await widget.api.wakeupConfig();
      final key=config['webpush_public_key'] as String?;
      if(key==null||key.isEmpty)return false;
      final subscription=await webPushSubscription(key);
      if(subscription==null)return false;
      await widget.api.registerWakeToken(widget.eventId,widget.deviceId,'webpush',subscription);
      return true;
    }catch(e){
      debugPrint('SARCADE wake-up not registered: $e');
      return false;
    }
  }

  StreamSubscription<String>? _fcmRefresh; StreamSubscription<Map<String,dynamic>>? _fcmForeground;

  /// Registration remembered for Paramètres › Notifications (« Tester le
  /// réveil » moved there, 29 Oct 2026).
  Future<bool> _wakeupNoted() async=>wakeupRegistered.value=await _registerWakeup();

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
      operator:()=>(callsign:widget.callsign,aprsTxConsent:widget.aprsTxConsent),
      onHttpsAvailable:widget.onHttpsAvailable);
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
  /// Touch on an operator: pins his trace; a second touch removes it.
  void _tapStation(SarcadePosition p){
    final pinned=_traces.togglePin(p.deviceId);
    if(!pinned){setState((){if(_selectedDevice==p.deviceId){_selectedDevice=null;_trace=[];_history=[];_scrub=null;}});return;}
    unawaited(_select(p,move:false));
  }
  Future<void> _select(SarcadePosition p,{bool move=true}) async {
    if(_tab!=0)_goTab(0);
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
  void _selectReference(ReferenceSite site){
    final pick=_pickPoint;
    if(pick!=null){setState((){_pickPoint=null;_pickHint=null;});pick(LatLng(site.lat,site.lon),site);return;}
    setState((){_tab=0;_selectedReference=site;_showReferencePanel=true;_showPanel=false;});_map.move(LatLng(site.lat,site.lon),14);}
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
    _drawing.color=_profileDrawColor;
    _drawing.canSelect=(f)=>canMultiSelect(f,widget.deviceId,pco:isPco(widget.deviceId));
    _drawing.addListener(_onDrawingChanged);
  }
  /// Colour of new drawings chosen in the profile (Paramètres).
  /// Without a chosen colour, one given automatically for the event: the
  /// least used by the others, kept so that it does not change.
  int get _profileDrawColor{
    final chosen=widget.store.storedConfig()?['draw_color'] as int?;
    if(chosen!=null)return chosen;
    final key='auto_color:${widget.eventId}';
    final kept=int.tryParse(widget.store.preference(key)??'');
    if(kept!=null)return kept;
    final c=autoColor(_drawing.features.where((f)=>f.createdBy!=null&&f.createdBy!=widget.deviceId).map((f)=>f.color));
    unawaited(widget.store.setPreference(key,'$c'));
    return c;
  }
  void _onDrawingChanged(){if(mounted)setState((){});}

  // Local edits: stored at once, then sent through the Outbox (ADR-001).
  void _onLocalFeatureChanged(MapFeature f,{required bool isNew}){
    widget.store.saveMapFeature(f.toJson());
    // Several objects at once: one logbook line (multi_select.dart).
    final g=_drawing.groupJson;
    _sync.queue(objectId:f.id,objectType:'map_feature',action:isNew?'create':'update',payload:{...f.toJson(),'group':?g});
  }

  void _onLocalFeatureDeleted(MapFeature f){
    widget.store.deleteMapFeature(f.id);
    _sync.queue(objectId:f.id,objectType:'map_feature',action:'delete',payload:{
      'id':f.id,'event_id':widget.eventId,'updated_by':widget.deviceId,'updated_at':DateTime.now().toUtc().toIso8601String(),'group':?_drawing.groupJson,
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
    if(objectType=='poi'&&!_sync.isPending('${payload['id']}')){
      unawaited(applyRemotePoi(_pois,widget.store,payload,widget.eventId).then((c){if(c&&mounted)setState((){});}));
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

  /// Graphic adjustment of a bearing (façon R&B, ATAK 1): a touch turns the
  /// line towards the point, a long press moves where it was taken.
  Bearing? _adjusting;
  void _adjustTowards(LatLng p){final b=_adjusting;if(b==null)return;
    setState(()=>_adjusting=b.copyWith(azimuthDeg:geo.bearingDeg(b.origin,p),method:'map',updatedBy:widget.deviceId,updatedAt:DateTime.now().toUtc()));}
  void _adjustOrigin(LatLng p){final b=_adjusting;if(b==null)return;
    setState(()=>_adjusting=b.copyWith(origin:p,method:'map',updatedBy:widget.deviceId,updatedAt:DateTime.now().toUtc()));}
  Future<void> _finishAdjust(bool keep) async {
    final b=_adjusting; setState(()=>_adjusting=null);
    if(keep&&b!=null)await _bearings.update(b);
  }
  Widget _adjustBanner(){
    final b=_adjusting!; final s=Theme.of(context).colorScheme;
    return Container(padding:const EdgeInsets.fromLTRB(14,8,8,8),decoration:glass(context,border:s.primary.withValues(alpha:0.6)),
      child:Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          Text('${b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}°',style:const TextStyle(fontSize:28,fontWeight:FontWeight.w600)),
          Text(S.t('bearings.adjustHelp'),style:TextStyle(fontSize:12,color:s.onSurfaceVariant)),
        ])),
        TextButton(onPressed:()=>_finishAdjust(false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>_finishAdjust(true),child:Text(S.t('common.save'))),
      ]));
  }

  Future<void> _onMapTap(TapPosition tap,LatLng point) async {
    final pick=_pickPoint;
    if(pick!=null){setState((){_pickPoint=null;_pickHint=null;});pick(point,null);return;}
    if(_adjusting!=null){_adjustTowards(point);return;}
    if(_aim!=null){_aimClick(tap,point);return;}
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
    // Ctrl / Maj + clic, or « Sélection » on a phone: adds or removes an object.
    final keys=HardwareKeyboard.instance;
    if(hit!=null&&(_drawing.selectMode||keys.isControlPressed||keys.isMetaPressed||keys.isShiftPressed)){_drawing.toggle(hit.id);return;}
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
    if(_drawing.hasSelection){_drawing.select(null);closed=true;}
    if(_measure.active){unawaited(_measure.clear());closed=true;}
    if(_selectedDevice!=null||_trace.isNotEmpty){_selectedDevice=null;_trace=[];closed=true;}
    if(_selectedReference!=null){_selectedReference=null;closed=true;}
    if(compact&&(_showPanel||_showReferencePanel||_showRoutesPanel)){_showPanel=false;_showReferencePanel=false;_showRoutesPanel=false;_drawingRouteId=null;closed=true;}
    if(closed)setState((){});
    return closed;
  }

  /// « Ma position » (requests of 26 and 27 Oct 2026): first press centres
  /// the map on the device; then follow; then follow with the map turned
  /// like the phone (compass, true north with the WMM declination); a press
  /// goes back to follow, north up. Moving the map by hand stops it all.
  LatLng? _me; MeMode _meMode=MeMode.off; StreamSubscription? _meSub; StreamSubscription? _mapEvents;
  double? _heading;
  bool get _followMe=>_meMode!=MeMode.off;
  /// One button, each touch the next mode (locate_cycle.dart, 30 Oct 2026).
  LocateMode _locate=LocateMode.idle;
  Future<void> _myPosition() async {
    var next=nextLocateMode(_locate);
    if(next==LocateMode.me){
      if(_meMode==MeMode.compass){_stopCompass();_map.rotate(0);}
      _meMode=MeMode.off;
      if(!await _location.ensurePermission()){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('map.noPosition'))));
        return;
      }
      final p=await _location.current();
      if(p==null||!mounted){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('map.noPosition'))));return;}
      setState((){_me=LatLng(p.latitude,p.longitude);_locate=LocateMode.me;});
      _map.move(_me!,_map.camera.zoom<15?16:_map.camera.zoom);
      _watchMapMoves();
      return;
    }
    if(next==LocateMode.follow){
      setState((){_meMode=MeMode.follow;_locate=LocateMode.follow;});
      final me=_me; if(me!=null)_map.move(me,_map.camera.zoom);
      _startFollowingMe();
      return;
    }
    if(next==LocateMode.compass){
      if(await _startCompass()){if(mounted)setState((){_meMode=MeMode.compass;_locate=LocateMode.compass;});return;}
      next=LocateMode.all;
    }
    // Every operator framed; the following stops (the map stays put).
    if(_meMode==MeMode.compass){_stopCompass();_map.rotate(0);}
    _meSub?.cancel(); _meSub=null;
    setState((){_meMode=MeMode.off;_locate=LocateMode.all;});
    _fitOperators();
  }
  void _startFollowingMe(){
    if(_meSub!=null)return;
    _meSub=_location.positions().listen((p){
      if(!mounted)return;
      setState(()=>_me=LatLng(p.latitude,p.longitude));
      if(_followMe)_map.move(_me!,_map.camera.zoom);
    },onError:(_){});
  }
  /// Compass of the phone (shared_compass.dart); false without one
  /// (computer) or when refused.
  bool _compassOn=false;
  Future<bool> _startCompass() async {
    if(_compassOn)return true;
    if(!await hasCompass()||!mounted)return false;
    if(!SharedCompass.instance.start()){SharedCompass.instance.stop();return false;}
    _compassOn=true; SharedCompass.instance.addListener(_onMapCompass);
    return true;
  }
  void _onMapCompass(){
    final me=_me, magnetic=SharedCompass.instance.heading; if(!mounted||_meMode!=MeMode.compass||magnetic==null)return;
    final declination=me==null?0.0:magneticDeclination(me.latitude,me.longitude,DateTime.now().toUtc());
    final next=(magnetic+declination+360)%360;
    if(headingChanged(_heading,next)){_heading=next;_map.rotate(-next);setState((){});}
  }
  void _stopCompass(){if(_compassOn){_compassOn=false;SharedCompass.instance.removeListener(_onMapCompass);SharedCompass.instance.stop();}_heading=null;}
  void _stopFollowing(){
    if(_meMode==MeMode.compass){_stopCompass();_map.rotate(0);}
    setState((){_meMode=MeMode.off;_locate=LocateMode.idle;}); _meSub?.cancel(); _meSub=null;
  }
  /// Moving the map by hand stops the following.
  void _watchMapMoves(){
    _mapEvents??=_map.mapEventStream.listen((e){
      if((_followMe||_locate!=LocateMode.idle)&&e.source!=MapEventSource.mapController&&e.source!=MapEventSource.nonRotatedSizeChange&&e is MapEventMove)_stopFollowing();
      if(e is MapEventRotate||e is MapEventRotateEnd)setState((){});
      // « Suivre ma vue » (lot 11): the followed screens get the new view.
      if(e is MapEventMoveEnd||e is MapEventRotateEnd||e is MapEventFlingAnimationEnd||e is MapEventDoubleTapZoomEnd||(e is MapEventMove&&e.source==MapEventSource.mapController))_tvScreens.mapMoved();
    });
  }

  /// Floating buttons on the right of the map: map type, my position, and
  /// the compass when the map is turned (tap: north up).
  Widget _mapButtons(){
    // The controller is attached once the map is built (first frame).
    double rotation=0; try{rotation=_map.camera.rotation;}catch(_){}
    final rotated=rotation%360!=0;
    final scheme=Theme.of(context).colorScheme;
    // Right column (decision of 30 Oct 2026, 3 h 05): « Fond et affichage »,
    // position, SOS; the north arrow only while a navigation turns the map.
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.end,children:[
      // No dot « couche masquée » any more (decision of 30 Oct 2026, 12 h 48).
      _fab('map-layers',S.t('display.menu'),const Icon(Icons.tune),_chooseBasemap),
      const SizedBox(height:10),
      if(rotated&&_meMode!=MeMode.compass)...[
        _fab('map-north',S.t('map.north'),Transform.rotate(angle:-rotation*3.141592653589793/180,child:const Icon(Icons.explore_outlined)),(){
            _map.rotate(0);setState((){});}),
        const SizedBox(height:10),
      ],
      LocateButton(mode:_locate,fab:(tip,icon,active)=>_fab('map-me',tip,icon,_myPosition,
        background:active?scheme.primary:null,foreground:active?scheme.onPrimary:null)),
      // « Écrans » (lot 11): shown once a screen is allowed, blue while followed.
      TvScreensButton(controller:_tvScreens,onManage:_openTvScreens,
        fab:(tip,icon,onPressed,active)=>Padding(padding:const EdgeInsets.only(top:10),child:_fab('map-screens',tip,icon,onPressed,
          background:active?scheme.primary:null,foreground:active?scheme.onPrimary:null))),
      if(_sosVisible)...[const SizedBox(height:16),_sosButton()],
    ]);
  }

  bool get _showOrders=>widget.store.preference('show_orders:${widget.eventId}')!='0';
  bool get _allTraces=>widget.store.preference('traces_all:${widget.eventId}')=='1';
  bool get _aprsTraces=>aprsTracesFrom(widget.store.preference('traces_aprs:${widget.eventId}'));
  int get _traceWindow=>traceWindowFrom(widget.store.preference('trace_window'));
  Future<void> _setFlag(String key,bool v) async {await widget.store.setPreference('$key:${widget.eventId}',v?'1':null);if(mounted)setState((){});}
  late final TracesStore _traces=TracesStore(load:(id)=>widget.api.positionHistory(widget.eventId,id,limit:2000),onChanged:(){if(mounted)setState((){});});
  /// Stations whose trace is drawn: pinned ones, or every one with « Toutes les traces ».
  List<String> _traceIds(Iterable<SarcadePosition> onMap){
    final ids=tracedStations(onMap,pinned:_traces.pinned,all:_allTraces,aprs:_aprsTraces);
    if(ids.isNotEmpty)unawaited(_traces.ensure(ids));
    return ids;
  }
  final LayerHitNotifier<String> _routeHits=ValueNotifier(null);

  /// SOS on the map (decision of 29 Oct 2026, 12 h 14): any operator, held
  /// 2 s; « Fin de détresse » blinking while in distress. Always visible,
  /// drawing, bearing and choice of a point included (card « Détresse
  /// encore dans le menu Plus », 30 Oct 2026): no more entry in « Plus ».
  bool get _sosVisible=>true;
  Widget _sosButton()=>SosButton(inDistress:_inDistress,onTriggered:_sendDistress,onEnd:_distress);

  /// Floating button of 48 × 48 px (the small ones were 40 px).
  Widget _fab(String tag,String tooltip,Widget icon,VoidCallback onPressed,{Color? background,Color? foreground})=>
    withId('map.$tag',SizedBox(width:48,height:48,child:FloatingActionButton(heroTag:tag,tooltip:tooltip,onPressed:onPressed,
      backgroundColor:background,foregroundColor:foreground,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),child:icon)));

  /// Map search (request of 26 Oct 2026): what the device knows, then the
  /// addresses from the server. The chosen result gets a red pin; a tap on
  /// it opens the point menu (measure, navigate, open in, weather).
  LatLng? _searchPin;
  // --- Résection panel and « Toucher la carte » (menu Outils) ---
  bool _showResection=false;
  /// Échap closes the side panel opened last (escape_stack.dart).
  final _escapes=EscapeStack();
  bool _shiftDown=false;
  /// Maj + glisser (computer) or « Sélection » (phone): selection rectangle.
  bool get _rectSelecting=>(_drawing.selectMode||_shiftDown)&&!_drawing.isDrawing&&_aim==null&&!_bearings.taking&&_adjusting==null;
  void _onSelectionRect(Rect r){final cam=_map.camera;_drawing.addToSelection(featuresInRect(_drawing.features,r,cam.latLngToScreenOffset,radiusPx:_circleRadiusPx).map((f)=>f.id));}
  /// Selection mode: a drag moves the map, a pinch or the wheel zooms
  /// (card C1); the rectangle needs a long press first, or Maj.
  double _selZoom=0;
  void _onSelectionMoveStart(ScaleStartDetails d){_selZoom=_map.camera.zoom;}
  void _onSelectionMove(ScaleUpdateDetails d){
    final cam=_map.camera;
    final zoom=(_selZoom+math.log(d.scale)/math.ln2).clamp(cam.minZoom??1.0,cam.maxZoom??20.0).toDouble();
    final mid=cam.latLngToScreenOffset(cam.center);
    _map.move(cam.screenOffsetToLatLng(mid-d.focalPointDelta),zoom);
  }
  void _onSelectionWheel(PointerScrollEvent e){
    final cam=_map.camera;
    _map.move(cam.center,(cam.zoom-e.scrollDelta.dy/200).clamp(cam.minZoom??1.0,cam.maxZoom??20.0).toDouble());
  }
  void _onSelectionTap(Offset at){final cam=_map.camera;final hit=hitTest(_drawing.features,at,cam.latLngToScreenOffset,radiusPx:_circleRadiusPx);if(hit!=null){_drawing.toggle(hit.id);}else{_drawing.endSelection();}}
  void _syncEscapes()=>_escapes.sync([if(_showPanel)'teams',if(_showRoutesPanel)'routes',if(_showReferencePanel)'reference',if(_showResection)'resection',if(_deskId!=null)'desk',if(_chatPeer!=null)'chat']);
  /// A window open over the map (side panel, page beside the rail).
  bool get _mapPanelOpen=>mapPanelOpen(teams:_showPanel,reference:_showReferencePanel,routes:_showRoutesPanel,resection:_showResection,chat:_chatPeer!=null,desk:_deskId!=null);

  /// « Carte » (tab bar of a phone, rail of a computer; decision of the
  /// porteur, 31 Oct 2026, 1 h 14): every window closes and the map shows.
  /// What runs on the map itself (bearing, navigation, drawing, measure)
  /// goes on; drafts are kept.
  void _showMapOnly(){
    final nav=Navigator.of(context); final me=ModalRoute.of(context);
    nav.popUntil((r)=>r==me||r.isFirst);
    // The selection is not a work in progress like a bearing or a
    // navigation: « Carte » leaves it (card C1, 31 Oct 2026).
    if(_drawing.selectMode||_drawing.hasSelection)_drawing.endSelection();
    // « Toucher la carte » of the converter is a mode of a moment too (card
    // N2, 31 Oct 2026).
    if(_pickPoint!=null){_pickPoint=null;_pickHint=null;_resectionCtl.pick(null);}
    setState((){
      _tab=0;_builtTabs.add(0);_deskPage=null;_deskId=null;_chatPeer=null;
      _showPanel=false;_showReferencePanel=false;_selectedReference=null;
      _showRoutesPanel=false;_drawingRouteId=null;
      _showResection=false;_resectionCtl.result=null;
    });
  }

  bool _escapePanel(){_syncEscapes();return _escapes.escape((k)=>setState((){switch(k){
    case 'teams':_showPanel=false; case 'routes':_showRoutesPanel=false;_drawingRouteId=null;
    case 'reference':_showReferencePanel=false;_selectedReference=null; case 'chat':_chatPeer=null; case 'resection':_showResection=false;_resectionCtl.result=null;
    default:_deskId=null;_deskPage=null;}}));}
  final ResectionController _resectionCtl=ResectionController();
  void Function(LatLng point,ReferenceSite? site)? _pickPoint; String? _pickHint;
  void _startPick(String hint,void Function(LatLng point,ReferenceSite? site) done)=>setState((){_tab=0;_deskPage=null;_deskId=null;_pickHint=hint;_pickPoint=done;});
  void _cancelPick()=>setState((){_pickPoint=null;_pickHint=null;_resectionCtl.pick(null);});
  Iterable<Searchable> _searchables()=>[
    for(final p in _positions.values)// Subtitle: the label of the device, never « Opérateur » twice (revue n° 10).
    Searchable(SearchKind.operator,p.deviceId.replaceFirst('aprs:',''),p.deviceId.startsWith('aprs:')?'APRS':(p.label.trim()!=p.deviceId?p.label.trim():''),LatLng(p.lat,p.lon)),
    if(_adrasec)for(final r in _references.values)Searchable(SearchKind.reference,r.name,[r.callsign,r.subtype,r.description].whereType<String>().join(' '),LatLng(r.lat,r.lon)),
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
  // Revue d'ergonomie n° 1 (bloquant): the scale starts from the saved view,
  // not from zoom 11, then reads the camera once the map is ready.
  Timer? _saveViewTimer; late double _camZoom=_savedView?.zoom??11, _camLat=_savedView?.lat??48.8566;
  void _onCameraChanged(MapCamera camera){
    final zoomChanged=(camera.zoom-_camZoom).abs()>0.01||(camera.center.latitude-_camLat).abs()>0.05;
    _camZoom=camera.zoom; _camLat=camera.center.latitude;
    if(zoomChanged&&mounted)setState((){}); // scale bar
    _saveViewTimer?.cancel();
    _saveViewTimer=Timer(const Duration(seconds:2),()=>unawaited(widget.store.setPreference('view:${widget.eventId}',
      encodeView(camera.center.latitude,camera.center.longitude,camera.zoom))));
  }

  bool _darkTiles(BuildContext context)=>Theme.of(context).brightness==Brightness.dark&&!_basemap.id.contains('photo')&&!_basemap.id.contains('sat');


  /// Filter chips under the search (Google Maps), kept per event.
  bool get _showOperators=>widget.store.preference('show_ops:${widget.eventId}')!='0';
  bool get _showDrawings=>widget.store.preference('show_draw:${widget.eventId}')!='0';
  bool get _showPois=>widget.store.preference('show_poi:${widget.eventId}')!='0';
  Future<void> _setShown(String key,bool v) async {await widget.store.setPreference('$key:${widget.eventId}',v?null:'0');if(mounted)setState((){});}
  /// Sections of the layers panel: Terrain, Opération, Référentiel ADRASEC.
  /// Transparency of a map layer (Couches panel), kept on this device:
  /// ops (operators and points), draw (drawings), brg (bearings), ref (reference).
  /// One opacity per layer (layer_row.dart): ops, aprs, poi, draw, brg, high, relay.
  double _layerOpacity(String k)=>layerOpacityFrom(widget.store.preference,k);
  Future<void> _setLayerOpacity(String k,double v) async {
    await widget.store.setPreference('opacity:$k',v>=0.99?null:v.toStringAsFixed(2));
    if(mounted)setState((){});
  }
  Widget _faded(String k,Widget layer){final o=_layerOpacity(k);return o>=1?layer:Opacity(opacity:o,child:layer);}
  List<Widget> _fadedAll(String k,List<Widget> layers)=>[for(final l in layers)_faded(k,l)];

  List<Widget> _layerSections(BuildContext c,StateSetter refresh){
    Widget row(String label,bool on,Future<void> Function(bool) set,{String? op,Widget? trailing})=>LayerRow(label:label,on:on,trailing:trailing,
      onShown:(v) async {await set(v);refresh((){});},
      opacity:op==null?null:_layerOpacity(op),onOpacity:op==null?null:(v) async {await _setLayerOpacity(op,v);refresh((){});});
    return [
      layerSectionTitle(c,S.t('layers.teams'),first:true),
      row(S.t('chips.operators'),_showOperators,(v)=>_setShown('show_ops',v),op:'ops'),
      if(_adrasec)...[
        row('APRS',_showAprs,(v) async =>setState(()=>_showAprsPref=v),op:'aprs'),
        row(S.t('fixed.layer'),_showFixed,(v)=>_setFlag('show_fixed',v)),
      ],
      // A filter, not a layer: no slider.
      row(S.t('chips.withoutInternet'),_withoutInternetOnly,(v) async =>setState(()=>_withoutInternetOnly=v)),
      layerSectionTitle(c,S.t('layers.operation')),
      row(S.t('chips.drawings'),_showDrawings,(v)=>_setShown('show_draw',v),op:'draw'),
      if(_adrasec)...[
        row(S.t('chips.bearings'),_showBearings,(v)=>_setShown('show_brg',v),op:'brg'),
        _bearingColorBy(refresh),
      ],
      row('${S.t('poi.layer')} (${_pois.length})',_showPois,(v)=>_setShown('show_poi',v),op:'poi',
        trailing:poiSeeListLink(_pois.length,onTap:(){Navigator.pop(c);_openPoiList();})),
      row(S.t('order.layer'),_showOrders,(v)=>_setShown('show_orders',v)),
      if(_showOrders)...moveOrderList(c,isPco(widget.deviceId)?_moveOrders:_moveOrders.where((o)=>o.targetId==widget.deviceId||o.createdBy==widget.deviceId).toList(),
        onOpen:(o){Navigator.pop(c);_fitPoints([o.destination]);_showMoveOrder(o);}),
      row(S.t('traces.layer'),_allTraces,(v)=>_setFlag('traces_all',v),op:'traces'),
      // « Toutes les traces » → « Durée des traces » → « Inclure les stations
      // APRS » as a sub-option, indented (card of 30 Oct 2026, 17 h 45).
      if(_allTraces||_traces.pinned.isNotEmpty)traceWindowChips(_traceWindow,(w) async {await widget.store.setPreference('trace_window',w==defaultTraceWindow?null:'$w');refresh((){});if(mounted)setState((){});}),
      if(_allTraces&&_adrasec)Padding(padding:const EdgeInsets.only(left:24),child:row(S.t('traces.aprsInclude'),_aprsTraces,
        (v) async {await widget.store.setPreference('traces_aprs:${widget.eventId}',v?null:'0');if(mounted)setState((){});})),
      if(_adrasec)...[
        layerSectionTitle(c,S.t('layers.reference')),
        row(S.t('refs.highPoints'),_showHighPoints,(v) async =>setState(()=>_showHighPointsPref=v),op:'high'),
        row(S.t('refs.relays'),_showRelays,(v) async =>setState(()=>_showRelaysPref=v),op:'relay'),
      ],
      const SizedBox(height:12),
    ];
  }

  /// « Colorer les relevés par : Signal / Opérateur » (Filtres).
  Widget _bearingColorBy(void Function(VoidCallback) refresh)=>ListTile(title:Text(S.t('bearings.colorBy')),
    trailing:ChoicePills<bool>(compact:true,
      choices:[(value:false,label:S.t('bearings.colorSignal'),icon:null),(value:true,label:S.t('bearings.colorOperator'),icon:null)],
      selected:_brgByOperator,
      onSelected:(v) async {await widget.store.setPreference('brg_color:${widget.eventId}',v?'op':null);refresh((){});if(mounted)setState((){});}));

  /// « Équipes »: the stations and « À proximité » in one place, a screen on
  /// the phone, a panel next to the map on a computer.
  bool _favouritesOnly=false, _showOld=false;

  /// Three sections by freshness: Actifs (favourites first), Sans
  /// nouvelles (age shown), Anciens (folded).
  Widget _teamsList(List<SarcadePosition> sorted){
    final now=DateTime.now().toUtc(); final fav=_favourites;
    final shown=_favouritesOnly?sorted.where((p)=>fav.contains(p.deviceId)):sorted;
    final by={for(final x in Section.values)x:<SarcadePosition>[]};
    final fixed=shown.where(_isFixed).toList()..sort((a,b)=>a.label.compareTo(b.label));
    for(final p in shown.where((p)=>!_isFixed(p))){by[sectionOf(p.time.toUtc(),now,oldMin:_oldMin)]!.add(p);}
    final t=Theme.of(context);
    Widget head(String label,int n,{VoidCallback? onTap,bool? open})=>InkWell(onTap:onTap,child:Padding(
      padding:const EdgeInsets.fromLTRB(16,12,8,4),child:Row(children:[
        Expanded(child:Text('$label · $n',style:t.textTheme.labelLarge?.copyWith(color:t.colorScheme.onSurfaceVariant))),
        if(open!=null)Icon(open?Icons.expand_less:Icons.expand_more,size:20,color:t.colorScheme.onSurfaceVariant),
      ])));
    final active=sortStations(by[Section.active]!,fav);
    final silent=[...by[Section.silent]!]..sort((a,b)=>b.time.compareTo(a.time));
    final old=[...by[Section.old]!]..sort((a,b)=>b.time.compareTo(a.time));
    return ListView(children:[
      if(shown.isEmpty)Padding(padding:const EdgeInsets.all(16),child:Text(S.t(_favouritesOnly?'favourites.none':'operators.none'))),
      if(active.isNotEmpty)...[head(S.t('teams.active'),active.length),...active.map(_stationTile)],
      if(silent.isNotEmpty)...[head(S.t('teams.silent'),silent.length),...silent.map(_stationTile)],
      if(old.isNotEmpty)...[head(S.t('teams.old'),old.length,open:_showOld,onTap:()=>setState(()=>_showOld=!_showOld)),
        if(_showOld)...old.map(_stationTile)],
      if(fixed.isNotEmpty)...[head(S.t('fixed.section'),fixed.length,open:_showFixedList,onTap:()=>setState(()=>_showFixedList=!_showFixedList)),
        if(_showFixedList)...fixed.map(_stationTile)],
    ]);
  }

  Widget _teams(List<SarcadePosition> sorted,{required bool screen}){
    final list=Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const SizedBox(height:6),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Wrap(spacing:6,children:[
        FilterChip(avatar:const Icon(Icons.star_border,size:18),label:Text(S.t('favourites.only')),selected:_favouritesOnly,
          onSelected:(v)=>setState(()=>_favouritesOnly=v)),
        if(_adrasec&&_positions.values.any((p)=>p.isAprs))FilterChip(avatar:const Icon(Icons.settings_input_antenna,size:18),label:Text(S.t('operators.aprs')),selected:_showAprs,onSelected:(v)=>setState(()=>_showAprsPref=v)),
      ])),
      // Fixed help under the filters, never over the list (revue n° 46).
      if(_showAprs&&_positions.values.any((p)=>p.isAprs))Padding(padding:const EdgeInsets.fromLTRB(14,4,14,0),
        child:Text(S.t('operators.aprsHint'),style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child:_teamsList(sorted)),
    ]);
    final tabs=DefaultTabController(length:2,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      // Count of the stations above the two tabs (as the former panel).
      Padding(padding:const EdgeInsets.fromLTRB(14,14,14,4),child:Text(operatorsTitle(sorted.where((p)=>!_isFixed(p)).length,sorted.where(_isFixed).length),style:Theme.of(context).textTheme.titleMedium)),
      TabBar(tabs:[Tab(text:S.t('teams.list')),Tab(text:S.t('nearby.title'))]),
      Expanded(child:TabBarView(children:[list,_nearbyPanel(closable:false)])),
    ]));
    if(!screen)return tabs;
    return Scaffold(appBar:LinkedAppBar(title:Text(S.t('tabs.teams'))),body:tabs);
  }

  /// Phone « Plus »: a normal screen, a list of large buttons.
  Widget _moreScreen(List<_RailAction> items)=>Scaffold(appBar:LinkedAppBar(title:Text(S.t('tabs.more'))),
    body:ListView(padding:const EdgeInsets.symmetric(vertical:8),children:[
      for(final a in items)withId('more.${a.id}',ListTile(minTileHeight:64,leading:Badge(isLabelVisible:a.alert,smallSize:10,child:Icon(a.icon,size:28)),
        title:Text(a.label,style:const TextStyle(fontSize:17)),trailing:const Icon(Icons.chevron_right),onTap:a.onTap)),
    ]));


  /// Weather pill with the link dot (link_weather_pill.dart, decision of
  /// 30 Oct 2026, 1 h 30): the hour to come from the last forecast of the
  /// event, red when a vigilance is orange or red; the « Connecté » pill is
  /// gone, its dot is here; the word only when slowed or cut.
  Widget _linkWeatherPill(){
    final state=_started?serverLink(syncOk:_sync.lastSyncOk,realtime:_realtime.connected):null;
    final scheme=Theme.of(context).colorScheme;
    final colour=switch(state){ServerLink.direct=>const Color(0xFF2E9D4B),ServerLink.slowed=>Colors.orange,ServerLink.cut=>scheme.error,null=>scheme.outline};
    final label=state==null?S.t('links.starting'):S.t('links.${state.name}');
    final j=widget.store.cachedJson('weather:${widget.eventId}');
    final r=j==null?null:WeatherReport.fromJson(j);
    final next=r?.upcoming(DateTime.now(),n:1)??const [];
    final h=next.isEmpty?null:next.first;
    final alert=(r?.vigilance?.colorId??1)>=3;
    return LinkWeatherPill(dot:colour,linkTooltip:'${S.t('links.serverLink')} : $label',
      linkWord:state==ServerLink.slowed||state==ServerLink.cut?label:null,
      weatherIcon:h==null?null:weatherIcon(weatherKey(h.weatherCode)),
      weatherText:h==null?null:pillWeatherText(temperatureC:h.temperatureC,compact:_isCompact,
        wind:h.windKmh==null?null:'${windDirection(h.windDirectionDeg)} ${h.windKmh!.round()} km/h'),
      compact:_isCompact,
      alert:alert?vigilanceColor(r!.vigilance!.colorId):null,
      onLinks:_openDiagnostics,onWeather:()=>_openWeather());
  }

  /// « Suivi actif · 30 s » always in sight (aprs.fi « Beacon »); a tap
  /// opens the tracking settings (formerly the button at the bottom).
  Widget _trackingBadge(){
    final scheme=Theme.of(context).colorScheme; final on=_tracking.enabled;
    return Material(color:Colors.transparent,child:InkWell(borderRadius:BorderRadius.circular(pillHeight/2),onTap:_openTracking,
      child:Container(height:pillHeight,padding:const EdgeInsets.symmetric(horizontal:12),
        decoration:BoxDecoration(color:on?scheme.primaryContainer:scheme.surface.withValues(alpha:0.92),borderRadius:BorderRadius.circular(pillHeight/2),
          // Tonal pill without outline (revue n° 11, charte « autre action »).
          ),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(on?Icons.my_location:Icons.location_disabled_outlined,size:16,color:on?scheme.primary:scheme.onSurfaceVariant),const SizedBox(width:6),
          Text(on?S.t('tracking.on',{'interval':intervalLabel(_tracking.intervalS,S.t)}):S.t('tracking.start'),
            style:TextStyle(fontSize:12,color:on?scheme.onPrimaryContainer:scheme.onSurface)),
        ]))));
  }

  /// Scale bar (OsmAnd), from the current zoom and latitude.
  Widget _scaleBar(){
    final b=scaleBar(_camZoom,_camLat);
    // Own light background, dark ink, whatever the theme (revue n° 5).
    const c=mapInkText;
    return Container(padding:const EdgeInsets.fromLTRB(6,2,6,4),decoration:BoxDecoration(color:mapInkBackground,borderRadius:BorderRadius.circular(6)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
        Text(b.label,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:c)),
        Container(width:b.px,height:6,decoration:const BoxDecoration(border:Border(left:BorderSide(color:c,width:2),right:BorderSide(color:c,width:2),bottom:BorderSide(color:c,width:2)))),
      ]));
  }

  // --- Stations V2: freshness, source, APRS symbols, favourites, trace, proximity ---
  bool _withoutInternetOnly=false;
  List<SarcadePosition> _history=[]; int _traceHours=1; SarcadePosition? _scrub;
  int get _ageingMin=>(_ops.settings.raw['position_ageing_min'] as num?)?.toInt()??2;
  /// « Anciens » after this many minutes (Paramètres › Événement, 2 h by default).
  int get _oldMin=>(_ops.settings.raw['position_old_min'] as num?)?.toInt()??120;
  int get _staleMin=>(_ops.settings.raw['position_stale_min'] as num?)?.toInt()??10;
  Set<String> get _favourites=>parseFavourites(widget.store.preference('favourites'));
  Future<void> _toggleFavourite(String id) async {
    final f=_favourites; if(!f.remove(id))f.add(id);
    await widget.store.setPreference('favourites',encodeFavourites(f));
    if(mounted)setState((){});
    // Kept by the server for the email (every device of the person).
    unawaited(widget.api.patchMyPreferences({'favourites':f.toList()..sort()}).catchError((_)=>false));
  }

  /// Favourites of the person from the server; the first time, the ones of
  /// this device are sent.
  Future<void> _loadMyPreferences() async {
    try{
      final p=await widget.api.myPreferences();
      if(p==null)return;
      // Preferred colour of the person, kept by the server (every event).
      final colour=p['color'];
      final stored=widget.store.storedConfig();
      if(colour is int&&stored!=null&&stored['draw_color']!=colour){
        await widget.store.saveConfig({...stored,'draw_color':colour});
        _drawing.color=colour;_bearings.operatorColor=colour;
      }
      final remote=p['favourites'];
      if(remote is List){
        await widget.store.setPreference('favourites',encodeFavourites({for(final x in remote)'$x'}));
        if(mounted)setState((){});
      }else if(_favourites.isNotEmpty){
        await widget.api.patchMyPreferences({'favourites':_favourites.toList()..sort()});
      }
    }catch(e){
      debugPrint('SARCADE personal settings not read: $e');
    }
  }
  // Fixed APRS stations (fixed_stations.dart): forced by hand on this device.
  final MovementTracker _moves=MovementTracker();
  Map<String,String> get _forced=>parseForced(widget.store.preference('fixed_forced:${widget.eventId}'));
  bool _isFixed(SarcadePosition p)=>isFixedStation(p,forced:_forced[p.deviceId],moved:_moves.moved(p.deviceId),still:_moves.still(p.deviceId,DateTime.now().toUtc()));
  bool get _showFixed=>widget.store.preference('show_fixed:${widget.eventId}')=='1'&&_adrasec;
  bool _showFixedList=false;
  Future<void> _saveForced(Map<String,String> m) async {await widget.store.setPreference('fixed_forced:${widget.eventId}',encodeForced(m));if(mounted)setState((){});}
  Future<void> _forceFixed(String id,String v) async {
    final m=_forced;if(v=='auto'){m.remove(id);}else{m[id]=v;}await _saveForced(m);
    try{await widget.api.setAprsClass(widget.eventId,id,widget.deviceId,serverKind(v));}catch(e){debugPrint('SARCADE APRS class not sent: $e');}
  }
  Future<void> _loadFixedClasses() async {try{final c=await widget.api.aprsClasses(widget.eventId);await _saveForced(forcedFromServer(c));}catch(_){/* offline: the cached classes stay */}}
  Future<void> _applyFixedClass(Map<String,dynamic> d) async {
    final id='${d['device_id']??''}';if(id.isEmpty)return;final m=_forced;final k='${d['kind']??''}';
    if(k=='fixed'){m[id]='f';}else if(k=='mobile'){m[id]='m';}else{m.remove(id);}await _saveForced(m);
  }
  Marker _fixedMarker(SarcadePosition p)=>Marker(point:LatLng(p.lat,p.lon),width:22,height:22,child:Tooltip(message:p.label,child:GestureDetector(onTap:()=>_tapStation(p),
    child:Opacity(opacity:0.7,child:_stationIcon(p,size:20)))));
  Future<void> _setTraceHours(int h) async {
    setState((){_traceHours=h;_scrub=null;_trace=traceWithin(_history,DateTime.now().toUtc(),h);});
  }

  Color _stationColor(SarcadePosition p){
    // Day colours on the map and in the lists, both themes (revue n° 5, 45).
    final s=mapMarkerScheme;
    if(p.deviceId==widget.deviceId)return s.tertiary;
    return p.isAprs?s.secondary:s.primary;
  }

  Widget _stationIcon(SarcadePosition p,{double size=34}){
    final s=mapMarkerScheme; final now=DateTime.now().toUtc();
    final f=freshness(p.time.toUtc(),now,ageingMin:_ageingMin,staleMin:_staleMin);
    final color=f==Freshness.stale?s.outline:_stationColor(p);
    final sym=p.isAprs?aprsSymbol(p.aprsSymbol):null;
    // Same letters as the avatars of the lists and Messages (revue n° 8).
    final initials=avatarInitials(p.label.trim().isEmpty?p.deviceId:p.label);
    return Stack(clipBehavior:Clip.none,alignment:Alignment.center,children:[
      Container(width:size,height:size,alignment:Alignment.center,
        decoration:BoxDecoration(color:s.surface,shape:sym?.overlay!=null?BoxShape.rectangle:BoxShape.circle,borderRadius:sym?.overlay!=null?BorderRadius.circular(8):null,
          border:Border.all(color:color,width:f==Freshness.stale?1.5:2.5)),
        child:sym==null?Text(initials,style:TextStyle(fontSize:size*0.3,fontWeight:FontWeight.w800,color:color))
          :sym.overlay!=null?Text(sym.overlay!,style:TextStyle(fontSize:size*0.45,fontWeight:FontWeight.w800,color:color))
          :Icon(sym.icon,size:size*0.58,color:color)),
      // Heading of a moving station (aprs.fi).
      if(p.headingDeg!=null&&(p.speedMps??0)>0.5)Positioned.fill(child:Transform.rotate(angle:p.headingDeg!*3.141592653589793/180,
        child:Align(alignment:Alignment.topCenter,child:Transform.translate(offset:const Offset(0,-9),child:Icon(Icons.navigation,size:14,color:color))))),
    ]);
  }

  /// Station markers, grouped with a number when they overlap (Tesla).
  List<Marker> _stationMarkers(List<SarcadePosition> list){
    final now=DateTime.now().toUtc(); final s=mapMarkerScheme;
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
    final s=mapMarkerScheme;
    final f=freshness(p.time.toUtc(),now,ageingMin:_ageingMin,staleMin:_staleMin);
    return Marker(point:LatLng(p.lat,p.lon),width:170,height:64,alignment:Alignment.topCenter,child:GestureDetector(onTap:()=>_tapStation(p),
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
    return ListTile(selected:_selectedDevice==p.deviceId,leading:p.isAprs?_stationIcon(p,size:32):operatorAvatar(p.deviceId,label:p.label,radius:16,stale:f==Freshness.stale),
      title:Text(p.label,style:TextStyle(decoration:f==Freshness.stale?TextDecoration.lineThrough:null)),
      // Version in the sheet only, not in the list (revue n° 43).
      subtitle:Text([_sourceLabel(p),ageLabel(p.time.toUtc(),now)].join(' · '),
        style:TextStyle(color:f==Freshness.fresh?null:s.tertiary)),
      trailing:IconButton(tooltip:S.t(fav?'favourites.remove':'favourites.add'),onPressed:()=>_toggleFavourite(p.deviceId),
        visualDensity:VisualDensity.compact,iconSize:20,
        icon:Icon(fav?Icons.star:Icons.star_border,color:fav?s.tertiary:s.onSurfaceVariant)),
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
            // APRS station linked to a terminal: its callsign stays visible
            // (« PCO-demo · F4JPO-5 », decision of 28 Oct 2026).
            Text(p.isAprs&&p.callsign!=null&&p.callsign!.isNotEmpty&&p.callsign!.toUpperCase()!=p.label.toUpperCase()
              ?'${p.label} · ${p.callsign}':p.label,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            Text(details.join(' · '),style:TextStyle(fontSize:12,color:f==Freshness.fresh?s.onSurfaceVariant:s.tertiary)),
            if(!p.isAprs&&(_deviceLine(p.deviceId)?.isNotEmpty??false))Text(_deviceLine(p.deviceId)!,style:TextStyle(fontSize:12,color:s.onSurfaceVariant)),
          ])),
          IconButton(tooltip:S.t(fav?'favourites.remove':'favourites.add'),onPressed:()=>_toggleFavourite(p.deviceId),icon:Icon(fav?Icons.star:Icons.star_border,color:fav?s.tertiary:null)),
          // « Discuter »: direct chat with this operator (not with myself, not an APRS station).
          if(!p.isAprs&&p.deviceId!=widget.deviceId)IconButton(tooltip:S.t('operators.chat'),onPressed:()=>setState((){_chatPeer=p.deviceId;_deskPage=null;_deskId=null;}),icon:const Icon(Icons.chat_outlined)),
          IconButton(tooltip:S.t('common.close'),onPressed:()=>setState((){_selectedDevice=null;_trace=[];_history=[];_scrub=null;}),icon:const Icon(Icons.close)),
        ]),
        if(callsignAmong([p.callsign,p.label,_devices[p.deviceId]?['callsign']?.toString()]) case final call?)Padding(padding:const EdgeInsets.only(top:6),child:CallsignLinks(callsign:call)),
        if(p.isAprs)Padding(padding:const EdgeInsets.only(top:8),child:Row(children:[
          Text(S.t('fixed.kind'),style:const TextStyle(fontSize:13)),const SizedBox(width:8),
          Flexible(child:ChoicePills<String>(compact:true,selected:_forced[p.deviceId]??'auto',onSelected:(v)=>_forceFixed(p.deviceId,v),
            choices:[(value:'auto',label:S.t(_isFixed(p)?'fixed.autoFixed':'fixed.autoMobile'),icon:null),(value:'f',label:S.t('fixed.fixed'),icon:null),(value:'m',label:S.t('fixed.mobile'),icon:null)])),
        ])),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),decoration:BoxDecoration(color:s.surfaceContainerHigh,borderRadius:BorderRadius.circular(10)),
          child:Text([_sourceLabel(p),if(p.aprsPath?.isNotEmpty==true)S.t('station.via',{'path':p.aprsPath})].join(' · '),style:const TextStyle(fontSize:12,fontFamily:'monospace'))),
        const SizedBox(height:8),
        Row(children:[
          Text(S.t('station.trace'),style:const TextStyle(fontSize:13)),const SizedBox(width:8),
          for(final h in const [1,6,24])Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text('$h h'),selected:_traceHours==h,onSelected:(_)=>_setTraceHours(h),visualDensity:VisualDensity.compact)),
          if(_traceLoading)const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),
        ]),
        // Hidden when every point has the same minute (revue n° 34).
        if(_trace.length>1&&hm(_trace.first.time)!=hm(_trace.last.time))...[
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
  Widget _nearbyPanel({bool closable=true}){
    final s=Theme.of(context).colorScheme;
    final from=_searchPin??_measure.target??_mapCentre();
    final fromLabel=_searchPin!=null?S.t('nearby.fromPin'):_measure.target!=null?S.t('nearby.fromTarget'):S.t('nearby.fromCentre');
    final items=<({String title,String subtitle,LatLng at,Widget icon,VoidCallback onTap})>[
      for(final p in _positions.values)(title:p.label,subtitle:'${_sourceLabel(p)} · ${ageLabel(p.time.toUtc(),DateTime.now().toUtc())}',at:LatLng(p.lat,p.lon),icon:_stationIcon(p,size:30),onTap:()=>_select(p)),
      for(final r in _references.values)(title:r.name,subtitle:r.subtitle,at:LatLng(r.lat,r.lon),icon:Icon(r.isHighPoint?Icons.terrain:Icons.cell_tower,color:s.secondary),onTap:()=>_selectReference(r)),
    ];
    final list=from==null?<Nearby<({String title,String subtitle,LatLng at,Widget icon,VoidCallback onTap})>>[]:nearest(from,items,(i)=>i.at);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(closable)Padding(padding:const EdgeInsets.fromLTRB(14,12,6,0),child:Text(S.t('nearby.title'),style:Theme.of(context).textTheme.titleMedium))
      else const SizedBox(height:10),
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
  int _brgStrength=0;
  bool get _showBearings=>widget.store.preference('show_brg:${widget.eventId}')!='0'&&_adrasec;
  String get _brgSearch=>widget.store.preference('brg_search:${widget.eventId}')??'';
  /// Default frequencies of the server, cached for offline use.
  List<SignalChoice> get _signalDefaults=>decodeSignals(widget.store.preference('signal_defaults'));
  /// Signals typed with « Autre… » during this session.
  final List<SignalChoice> _extraSignals=[];
  List<SignalChoice> get _signalMenu=>signalMenu(_bearings.all,_signalDefaults,extra:_extraSignals);
  SignalChoice? get _currentSignal=>_brgSearch.isEmpty?null:signalFor(_signalMenu,_brgSearch);
  Future<void> _loadSignalDefaults() async {
    try{
      final body=await widget.api.signalDefaults();
      await widget.store.setPreference('signal_defaults',body);
      if(mounted)setState((){});
    }catch(_){/* offline or older server: cached or built-in list */}
  }

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
    _bearings.operatorColor=_profileDrawColor;
    unawaited(_loadSignalDefaults());
    // Pre-selection: the last signal I used in the event.
    if(_brgSearch.isEmpty){
      final mine=[..._bearings.all.where((b)=>b.createdBy==widget.deviceId&&b.search.isNotEmpty)]..sort((a,b)=>b.takenAt.compareTo(a.takenAt));
      if(mine.isNotEmpty)unawaited(widget.store.setPreference('brg_search:${widget.eventId}',mine.first.search));
    }
    _bearings.addListener((){
      // Taking a bearing shows the « Relevés » filter again if it was off.
      if(_bearings.taking&&!_showBearings)unawaited(_setShown('show_brg',true));
      if(!_bearings.taking)_aim=null;
      if(mounted)setState((){});
    });
  }

  Bearing? _bearingDraft()=>_bearings.taking?_bearings.draft(strength:_brgStrength,search:_brgSearch,lengthM:_aim?.lengthM,takenAt:_aim?.takenAt,method:_aim==null?null:'map'):null;
  /// Computer: bearing aimed with the mouse (bearing_aim.dart).
  BearingAim? _aim;
  void _aimHover(PointerHoverEvent e){final a=_aim;if(a==null||a.fixed)return;
    if(a.follow(_map.camera.screenOffsetToLatLng(e.localPosition),snap:HardwareKeyboard.instance.isShiftPressed))_bearings.setManual(a.azimuthDeg);}
  void _aimClick(TapPosition tap,LatLng p){final a=_aim!;
    if(a.fixed){final t=a.tip, at=tap.relative;if(t!=null&&at!=null&&nearTip(at,_map.camera.latLngToScreenOffset(t))){setState(a.release);}return;}
    a.fix(p,snap:HardwareKeyboard.instance.isShiftPressed);_bearings.setManual(a.azimuthDeg);}
  void _cancelAim(){_aim=null;_bearings.stopTaking();}
  /// Mouse bearing started (new or changed): map centred on its origin (30 Oct 2026, 12 h 44).
  void _startAim(BearingAim a){setState(()=>_aim=a);_focusBearing(a.origin);}
  /// Bearing started (finger, mouse, « Modifier »): the map glides once so
  /// that its origin sits in the middle of the visible part, never under
  /// the bearing sheet (31 Oct 2026); afterwards the map is free.
  void _focusBearing(LatLng origin){
    Size size; try{size=Size(_map.camera.nonRotatedSize.width,_map.camera.nonRotatedSize.height);}catch(_){return;}
    final wide=MediaQuery.sizeOf(context).width>=_compactWidth;
    glideMapTo(_map,origin,focus:bearingFocus(size,phone:!wide,rightSheetPx:wide&&_aim!=null?bearingSheetWidth+24:0));
  }
  /// « Modifier » on a computer: mouse arrow from the same origin, panel
  /// prefilled; Échap or a right click leaves the bearing as it was.
  Future<void> _editWithMouse(Bearing b) async {
    await _bearings.startTaking(from:b.origin);
    if(!mounted)return;
    final a=BearingAim.edit(b);
    _bearings.setManual(a.azimuthDeg);
    if(b.search.isNotEmpty)await _setSignal(b.search);
    if(mounted){setState(()=>_brgStrength=b.strength);_startAim(a);}
  }
  bool get _brgByOperator=>widget.store.preference('brg_color:${widget.eventId}')=='op';
  Future<void> _setSignal(String v) async {await widget.store.setPreference('brg_search:${widget.eventId}',v.isEmpty?null:v);if(mounted)setState((){});}

  /// Top of the screen while taking a bearing: azimuth in big figures,
  /// position, accuracy, time (direction-finding app of the captures).
  Widget _bearingHud(){
    final s=Theme.of(context).colorScheme; final b=_bearings; final az=b.trueDeg; final p=b.position;
    final mouse=_aim!=null, decl=b.declinationDeg, mag=mouse?(az==null||decl==null?null:normDeg(az-decl)):b.magneticDeg;
    final t=DateTime.now();
    if(mouse){return MouseBearingHud(trueDeg:az,magneticDeg:mag,position:p,accuracyM:b.accuracyM,time:t,onClose:_cancelAim,
      decoration:glass(context,border:s.primary.withValues(alpha:0.6)));}
    final deco=glass(context,border:s.primary.withValues(alpha:0.6));
    // No compass: « Relevé » with a visible field.
    // The field stays while the azimuth is typed (no compass).
    if(!b.hasCompass){
      return TypedBearingHud(position:p,accuracyM:b.accuracyM,time:t,onClose:_cancelAim,decoration:deco,
        onAzimuth:(d)=>setState(()=>_bearings.setManual(d)));
    }
    // Compass (card « Relevé à la boussole, bandeau compact », 16 h 25):
    // the same compact line as with the mouse, help in the ⓘ.
    final typed=b.manualDeg!=null;
    return MouseBearingHud(trueDeg:az,magneticDeg:typed?null:mag,position:p,accuracyM:b.accuracyM,time:t,onClose:_cancelAim,decoration:deco,
      help:S.t('bearings.aimHelp'),trueLabel:S.t(typed?'bearings.typed':'bearings.true'),
      below:!typed&&(b.hasCompass||b.needsCalibration||b.averaging)?CompassStatus(accuracyDeg:b.compassAccuracyDeg,calibrate:b.needsCalibration,averaging:b.averaging):null);
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
      // « Signal recherché »: the signals of the event first, one touch
      // takes the same again; the current one stays for the next bearings.
      Text(S.t('bearings.signal'),style:TextStyle(fontSize:12,color:s.onSurfaceVariant)),
      const SizedBox(height:4),
      _signalDropdown(),
      const SizedBox(height:10),
      Row(children:[
        Text(S.t('bearings.strength'),style:const TextStyle(fontSize:13)),const SizedBox(width:8),
        Expanded(child:Row(children:[for(var i=1;i<=9;i++)Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:1.5),child:Semantics(button:true,label:'S$i',selected:_brgStrength==i,
          child:InkWell(onTap:()=>setState(()=>_brgStrength=_brgStrength==i?0:i),child:Container(height:22,decoration:BoxDecoration(
            color:i<=_brgStrength?s.primary:s.surfaceContainerHighest,borderRadius:BorderRadius.circular(4)))))))])),
        const SizedBox(width:8),
        SizedBox(width:28,child:Text(_brgStrength==0?'':'S$_brgStrength',style:TextStyle(fontWeight:FontWeight.w700,color:s.primary))),
      ]),
      if(_aim!=null)Padding(padding:const EdgeInsets.only(top:10),child:AimFields(azimuthDeg:_aim!.azimuthDeg,takenAt:_aim!.takenAt,
        onAzimuth:(d){_aim!.type(d);_bearings.setManual(d);},onTime:(t)=>setState(()=>_aim!.takenAt=t))),
      if(effect!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(effect,style:TextStyle(fontSize:13,color:s.onSurfaceVariant))),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:FilledButton.icon(style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52)),
          onPressed:draft==null||_bearings.averaging?null:() async {
            final sig=_currentSignal;
            // Mouse: the free length becomes the usual one only now.
            final a=_aim;
            final changed=a?.edited(strength:_brgStrength,search:_brgSearch,exercise:sig?.exercise??false,frequencyMhz:sig?.frequencyMhz,
              lengthM:savedLengthM(),by:widget.deviceId,at:DateTime.now().toUtc());
            if(changed!=null){_bearings.stopTaking();await _bearings.update(changed);if(mounted)setState(()=>_brgStrength=0);return;}
            final b=await _bearings.save(strength:_brgStrength,search:_brgSearch,exercise:sig?.exercise??false,frequencyMhz:sig?.frequencyMhz,
              lengthM:a==null?null:savedLengthM(),takenAt:a?.takenAt,method:a==null?null:'map');
            if(b!=null&&mounted){setState(()=>_brgStrength=0);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('bearings.saved',{'v':b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')})+(_bearings.lastSpreadDeg==null?'':' (±${_bearings.lastSpreadDeg!.toStringAsFixed(0)}°)'))));}
          },
          icon:const Icon(Icons.track_changes),label:Text(S.t('bearings.save')))),
        if(_aim==null)...[const SizedBox(width:8),
        RoundIconButton(tooltip:S.t('bearings.typeAzimuth'),size:48,onPressed:_typeAzimuth,icon:Icons.edit_outlined),
        const SizedBox(width:4),
        RoundIconButton(tooltip:S.t('bearings.useMapCentre'),size:48,
          onPressed:(){final c=_mapCentre();if(c!=null)_bearings.setPosition(c);},icon:Icons.filter_center_focus)],
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

  /// « Signal recherché »: one list, the signals of the event first, then
  /// the default frequencies, « Autre… » last.
  Widget _signalDropdown(){
    final s=Theme.of(context).colorScheme;
    final menu=_signalMenu;
    // Same signal saved with another apostrophe: the line of the list.
    final current=_currentSignal?.name??_brgSearch;
    final items=[...menu,if(current.isNotEmpty&&!menu.any((m)=>m.name==current))SignalChoice(label:current)];
    Widget row(SignalChoice c)=>Row(children:[
      Icon(Icons.circle,size:12,color:Color(searchColor(c.name))),const SizedBox(width:8),
      Flexible(child:Text(c.name,overflow:TextOverflow.ellipsis)),
      if(c.exercise)...[const SizedBox(width:6),const ExerciseBadge()],
    ]);
    return DropdownButtonHideUnderline(child:Container(padding:const EdgeInsets.symmetric(horizontal:10),
      decoration:BoxDecoration(border:Border.all(color:s.outlineVariant),borderRadius:BorderRadius.circular(12)),
      child:DropdownButton<String>(isExpanded:true,value:current.isEmpty?null:current,hint:Text(S.t('bearings.signalChoose')),
        items:[
          for(final c in items)DropdownMenuItem(value:c.name,child:row(c)),
          DropdownMenuItem(value:_otherSignal,child:Row(children:[Icon(Icons.add,size:18,color:s.primary),const SizedBox(width:6),
            Text(S.t('bearings.signalOther'),style:TextStyle(color:s.primary,fontWeight:FontWeight.w600))])),
        ],
        onChanged:(v){if(v==_otherSignal){_newSignal();}else if(v!=null){_setSignal(v);}})));
  }
  static const _otherSignal='\u0000other';

  /// « Autre… »: frequency, optional label, real or exercise.
  Future<void> _newSignal() async {
    final f=TextEditingController(), l=TextEditingController(); var exercise=false;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('bearings.signalNew')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(controller:f,autofocus:true,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:InputDecoration(labelText:S.t('bearings.signalFreq'),suffixText:'MHz',hintText:'121,375')),
        const SizedBox(height:8),
        TextField(controller:l,maxLength:50,decoration:InputDecoration(labelText:S.t('bearings.signalLabel'))),
        ChoicePills<bool>(choices:[(value:false,label:S.t('bearings.signalReal'),icon:null),(value:true,label:S.t('bearings.signalExercise'),icon:null)],
          selected:exercise,onSelected:(v)=>set(()=>exercise=v)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.ok')))])));
    final freq=parseMhz(f.text), label=l.text.trim();
    f.dispose(); l.dispose();
    if(ok!=true)return;
    if(freq==null&&label.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('bearings.signalInvalid'))));return;}
    final sig=SignalChoice(label:label,frequencyMhz:freq,exercise:exercise);
    _extraSignals.removeWhere((x)=>x.name==sig.name);
    _extraSignals.insert(0,sig);
    await _setSignal(sig.name);
  }

  /// Details of a bearing; change or delete for its author or the PCO.
  Future<void> _showBearingSheet(Bearing b) async {
    final can=b.canEdit(widget.deviceId,isPco(widget.deviceId));
    final l=b.takenAt.toLocal(); String two(int v)=>v.toString().padLeft(2,'0');
    final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,0,20,12),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        // « vrai » at the size of the lines below, on the baseline of the
        // azimuth (card « Fiche d'un relevé, « vrai » trop grand », 17 h 38).
        Row(crossAxisAlignment:CrossAxisAlignment.baseline,textBaseline:TextBaseline.alphabetic,children:[
          Text('${b.azimuthDeg.toStringAsFixed(0).padLeft(3,'0')}°',style:const TextStyle(fontSize:32,fontWeight:FontWeight.w600)),
          const SizedBox(width:6),
          Text(S.t('bearings.true'),style:Theme.of(c).textTheme.bodyMedium),
          if(b.exercise)...[const SizedBox(width:10),const ExerciseBadge()]]),
        // Never cut: on two lines when needed.
        Text([if(b.search.isNotEmpty)b.search,b.createdBy,'${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}',if(b.strength>0)'S${b.strength}',
          S.t('bearings.method.${b.method}')].join(' · '),softWrap:true,maxLines:3),
        if(b.comment.isNotEmpty)Padding(padding:const EdgeInsets.only(top:6),child:Text(b.comment)),
        Text(S.t('bearings.lineCone',{'l':geo.formatDistance(b.lengthM),'c':b.coneDeg.toStringAsFixed(0)}),style:TextStyle(fontSize:12,color:Theme.of(c).colorScheme.onSurfaceVariant)),
        PlaceLine(describer:_places,point:b.origin),
        const SizedBox(height:8),
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.place_outlined),title:Text(S.t('bearings.fromOrigin')),onTap:()=>Navigator.pop(c,'origin')),
        if(can)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.open_with),title:Text(S.t('bearings.adjust')),onTap:()=>Navigator.pop(c,'adjust')),
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
    // Computer: the arrow follows the mouse again, as when taking it.
    if(choice=='edit'){if(_isCompact){await _editBearing(b);}else{await _editWithMouse(b);}}
    if(choice=='adjust')setState(()=>_adjusting=b);
  }

  Future<void> _editBearing(Bearing b) async {
    final az=TextEditingController(text:b.azimuthDeg.toStringAsFixed(1)), cone=TextEditingController(text:b.coneDeg.toStringAsFixed(0)),
      len=TextEditingController(text:(b.lengthM/1000).toStringAsFixed(1)), target=TextEditingController(text:b.search), comment=TextEditingController(text:b.comment),
      when=TextEditingController(text:hhmm(b.takenAt));
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('bearings.edit')),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:az,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:S.t('bearings.azimuth'),suffixText:'°')),
      TextField(controller:cone,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:S.t('bearings.cone'),suffixText:'± °')),
      TextField(controller:len,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:S.t('bearings.length'),suffixText:'km')),
      TextField(controller:target,decoration:InputDecoration(labelText:S.t('bearings.signal'))),
      TextField(controller:comment,decoration:InputDecoration(labelText:S.t('bearings.comment'))),
      // Real time of the bearing, set afterwards (taken without GPS).
      TextField(controller:when,keyboardType:TextInputType.datetime,decoration:InputDecoration(labelText:S.t('bearings.time'),hintText:'14:05')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.save')))]));
    double? n(TextEditingController t)=>double.tryParse(t.text.replaceAll(',','.').trim());
    if(ok==true){
      final a=n(az),cn=n(cone),ln=n(len);
      await _bearings.update(b.copyWith(azimuthDeg:a==null||a<0||a>360?null:a%360,coneDeg:cn==null||cn<0||cn>45?null:cn,
        lengthM:ln==null||ln<0.1||ln>200?null:ln*1000,target:'',search:target.text.trim(),comment:comment.text.trim(),
        takenAt:withHhmm(b.takenAt,when.text),
        updatedBy:widget.deviceId,updatedAt:DateTime.now().toUtc()));
    }
    for(final t in [az,cone,len,target,comment,when]){t.dispose();}
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
  Future<void> _exportGeoJson({List<MapFeature>? only,ExportFormat format=ExportFormat.geojson}) async {
    final messenger=ScaffoldMessenger.of(context);
    final stamp=DateTime.now().toIso8601String().substring(0,16).replaceAll(RegExp(r'[:T]'),'-');
    final name='sarcade-objets-${widget.eventId}-$stamp.${format.extension}'.replaceAll(RegExp(r'[\\/:*?"<>|]'),'_');
    final bytes=exportFeatures(only??_drawing.features,format);
    String? localPath;
    try{localPath=await saveFile(name,bytes,mimeType:format.mimeType);}catch(_){localPath=null;}
    var shared=false;
    try{await widget.api.uploadFile(widget.eventId,widget.deviceId,name,format.mimeType,bytes);shared=true;}catch(_){}
    if(!mounted)return;
    final count=only?.length??_drawing.features.length;
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
        // Échap still closes the panel being typed in (search of a list).
        return event.logicalKey==LogicalKeyboardKey.escape&&_aim==null&&_escapePanel()?KeyEventResult.handled:KeyEventResult.ignored;
      }
      final keys=HardwareKeyboard.instance;
      final ctrl=keys.isControlPressed||keys.isMetaPressed;
      final key=event.logicalKey;
      bool run(VoidCallback action){action();return true;}
      final handled=switch(key){
        LogicalKeyboardKey.escape when _aim!=null=>run(_cancelAim),
        LogicalKeyboardKey.delete||LogicalKeyboardKey.backspace when _drawing.hasSelection=>run(()=>unawaited(deleteSelection(context,_drawing))),
        LogicalKeyboardKey.keyZ when ctrl&&keys.isShiftPressed=>run(_drawing.redo),
        LogicalKeyboardKey.keyZ when ctrl=>run(_drawing.undo),
        LogicalKeyboardKey.keyY when ctrl=>run(_drawing.redo),
        LogicalKeyboardKey.keyD when ctrl&&_drawing.hasSelection=>run(()=>_drawing.duplicateSelected()),
        LogicalKeyboardKey.enter||LogicalKeyboardKey.numpadEnter when _drawing.canFinish=>run(()=>_drawing.finish()),
        LogicalKeyboardKey.escape when _drawing.isDrawing=>run(()=>_drawing.selectTool(null)),
        LogicalKeyboardKey.escape when _drawing.hasSelection||_drawing.selectMode=>run(_drawing.endSelection),
        // Card N1 of the cinématique review (31 Oct 2026): Échap also ends
        // « Toucher la carte » (converter), then closes the last window, then
        // clears the measure, then closes an empty drawing bar.
        LogicalKeyboardKey.escape when _pickPoint!=null=>run(_cancelPick),
        LogicalKeyboardKey.escape when _mapPanelOpen=>_escapePanel(),
        LogicalKeyboardKey.escape when _measure.active=>run((){unawaited(_measure.clear());setState((){});}),
        LogicalKeyboardKey.escape when _drawingTools&&_drawing.selection.isEmpty=>run(_toggleDrawingTools),
        LogicalKeyboardKey.escape=>_escapePanel(),
        _=>false,
      };
      return handled?KeyEventResult.handled:KeyEventResult.ignored;
    },
    child:child,
  );

  @override void dispose(){linkStatusOnTap=null;_tvScreens.dispose();if(currentMapView==_tvView)currentMapView=null;if(currentMapOptions==_tvOptions)currentMapOptions=null;_stopCompass();_webUpdateTimer?.cancel();_saveViewTimer?.cancel();_bearings.dispose();_positionsTimer?.cancel();_meSub?.cancel();_mapEvents?.cancel();AccessManager.instance.removeListener(_onAccessChanged);_fcmRefresh?.cancel();_fcmForeground?.cancel();if(registerWakeupHook==_wakeupNoted)registerWakeupHook=null;_opensSub?.cancel();_answersSub?.cancel();_rtSub?.cancel();_tracking.removeListener(_onOperationsChanged);_ops.removeListener(_onOperationsChanged);_tracking.dispose();_ops.dispose();_routes.removeListener(_onRoutesChanged);_nav.removeListener(_onNavigationChanged);_variantHits.dispose();_bearingHits.dispose();_routeHits.dispose();_routes.dispose();_nav.dispose();_graphs.removeListener(_onRoutesChanged);_graphs.dispose();_measure.removeListener(_onRoutesChanged);_measure.dispose();_syncUiTimer?.cancel();_sync.dispose();_realtime.dispose();_drawing.dispose();_resectionCtl.dispose();widget.api.close();super.dispose();}

  late final _tvNearby=TvNearbyWatcher(widget.api);
  // « Écrans » button of the map (lot 11).
  late final _tvScreens=TvScreensController(api:widget.api,eventId:widget.eventId);
  void _openTvScreens()=>_openDesk('tv',()=>TvScreensPage(key:const ValueKey('desk-tv'),api:widget.api,eventId:widget.eventId));
  /// Current view, for « Envoyer ma vue » on a TV (Paramètres › Affichage › Écrans).
  TvView? _tvView(){
    try{final c=_map.camera;return (center:c.center,zoom:c.zoom,basemapId:_basemap.id,tileUrl:_basemap.url,attribution:_basemap.attribution,basemapName:_basemap.name);}
    catch(_){return null;}
  }

  /// Filters and opacities of this map, applied by the TV (step 2).
  TvOptions _tvOptions()=>(
    layers:{'operators':_showOperators,'aprs':_showAprs,'offline':true,'drawings':_showDrawings,'bearings':_showBearings,
      'highpoints':_showHighPoints,'relays':_showRelays},
    // One opacity per layer, as in the Affichage tab (lot 4, 30 Oct 2026).
    opacity:{for(final k in tvOpacityKeys)k:_layerOpacity(k)},
    messages:true,
  );

  @override Widget build(BuildContext context){
    currentMapView=_tvView; currentMapOptions=_tvOptions;
    final sorted=_positions.values.where((p)=>(p.isAprs?_showAprs:_showOperators)&&(!_withoutInternetOnly||worksWithoutInternet(p)||p.deviceId==widget.deviceId)).toList()..sort((a,b)=>a.deviceId.compareTo(b.deviceId));
    // Old stations stay in the list and the search, not on the map.
    for(final p in _positions.values){if(p.isAprs)_moves.observe(p);}
    final onMap=sorted.where((p)=>p.deviceId==widget.deviceId||(sectionOf(p.time.toUtc(),DateTime.now().toUtc(),oldMin:_oldMin)!=Section.old&&(_showFixed||!_isFixed(p)))).toList();
    final selected=_selectedDevice==null?null:_positions[_selectedDevice];
    final traced=_traceIds(onMap.where((p)=>!_isFixed(p)));
    final screenWidth=MediaQuery.sizeOf(context).width;
    final compact=screenWidth<_compactWidth;
    _syncEscapes();
    // On a phone a panel takes most of the width, leaving a strip of map visible.
    double panelWidth(double w)=>compact?(screenWidth*0.85).clamp(0.0,w):w;
    // Phone (revue n° 52): Itinéraires and Résection on the whole screen,
    // under the status bar; folded while points are added on the map.
    final fullPanel=sidePanelFullScreen(screenWidth);
    final routeEntry=fullPanel&&_showRoutesPanel&&_drawingRouteId!=null?_routes.route(_drawingRouteId!):null;
    Widget routesPanel()=>RoutesPanel(onClose:_showMapOnly,onOpenIn:(p,l)=>unawaited(_openElsewhere(p,l)),
          controller:_routes,api:widget.api,actorId:widget.deviceId,selectedRouteId:_selectedRouteId,drawingRouteId:_drawingRouteId,
          groups:widget.store.groups(widget.eventId).map(CommGroup.fromJson).toList(),
          onSelect:(id)=>setState((){_selectedRouteId=id;if(id==null)_drawingRouteId=null;}),
          onDraw:(id)=>setState((){_drawingRouteId=id;_drawingClosure=false;}),
          onDrawClosure:()=>setState((){_drawingClosure=true;_drawingRouteId=null;_closureDraft.clear();}),
          onNavigate:_navigateTo,
          onFocus:_fitPoints,
          onSend:(text)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(api:widget.api,eventId:widget.eventId,
            actorId:widget.deviceId,sync:_sync,store:widget.store,initialText:text))),
        );
    // Over the map, not beside it: the map keeps its size underneath.
    Widget phonePanel(Widget child)=>Positioned.fill(child:Material(elevation:3,child:SafeArea(bottom:false,child:child)));
    void toggleOperators()=>setState((){_deskPage=null;_deskId=null;_showPanel=!_showPanel;if(_showPanel){_showReferencePanel=false;_showResection=false;}});
    void openFiles()=>_openDesk('files',()=>FilesPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId,store:widget.store,drawings:DrawingFileActions(importFile:_importFile,exportAll:_exportGeoJson,count:()=>_drawing.features.length)));
    void openMessages()=>_openMessages(fromButton:true);
    void showMap()=>_showMapOnly();
    void openSettings(){
      final b=widget.settingsBuilder;
      if(!compact&&b!=null){_openDesk('settings',b);}else{widget.onSettings?.call();}
    }
    // Phone « Plus » (decision of 30 Oct 2026, 3 h 10): Fichiers and
    // Paramètres; « Outils » is a tab, « Itinéraires » is in it.
    final more=<_RailAction>[
      _RailAction(Icons.folder_copy_outlined,S.t('map.files'),openFiles,id:'files'),
      if(widget.onSettings!=null)_RailAction(Icons.settings_outlined,S.t('map.settings'),widget.onSettings!,alert:diagnosticsAlert(),id:'settings'),
    ];
    // Computer: every entry visible, no « … » (decision of 29 Oct 2026,
    // 12 h 17); Carte and Messages are drawn by the rail itself, Paramètres
    // at the bottom.
    final rail=<_RailAction>[
      _RailAction(Icons.groups_outlined,S.t('tabs.teams'),toggleOperators,selected:_showPanel,id:'teams'),
      _RailAction(Icons.folder_copy_outlined,S.t('map.files'),openFiles,selected:_deskId=='files',id:'files'),
      // « Itinéraires » moved into « Outils » (29 Oct 2026); wrench icon, the
      // handyman glyph did not show on the web.
      _RailAction(Icons.build_outlined,S.t('tools.title'),_openTools,
        selected:_showResection||_showRoutesPanel||const {'tools','converter','tv','aprs','weather'}.contains(_deskId),id:'tools'),
    ];
    final railBottom=(widget.onSettings!=null||widget.settingsBuilder!=null)
      ?_RailAction(Icons.settings_outlined,S.t('map.settings'),openSettings,selected:_deskId=='settings',alert:diagnosticsAlert(),id:'settings'):null;
    // Blue while Messages is open, page or side panel (card « Bouton Messages
    // pas mis en évidence », 30 Oct 2026, 16 h 13): one button in blue.
    final messagesOn=messagesRailSelected(deskId:_deskId,chatPeer:_chatPeer);
    final railScheme=Theme.of(context).colorScheme;
    final messagesButton=IconButton(key:const ValueKey('rail-messages'),tooltip:S.t('map.messages'),onPressed:openMessages,icon:_messagesIcon(),isSelected:messagesOn,
      style:IconButton.styleFrom(fixedSize:const Size(48,48),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
        backgroundColor:messagesOn?railScheme.primaryContainer:null,foregroundColor:messagesOn?railScheme.primary:railScheme.onSurfaceVariant));
    final sosAlert=_sosAlert();
    final banners=OperationsBanners(settings:_ops.settings,update:_ops.update,
          alert:syncAlert(_sync.currentItems,DateTime.now(),_ops.settings.syncAlertMinutes),
          heldPhotos:_sync.lowBandwidth?widget.store.pendingUploads().length:0,
          onSyncNow:_retryAllUnsent,alertWhat:unsentWhat(_sync.currentItems),onOpenUnsent:_openDiagnostics,
          onUpdate:()=>downloadUpdate(context,widget.api,_ops.update),
          accessRequired:AccessManager.instance.requiredFor(widget.api.baseUrl),
          accessRenewBy:_accessRenewBy,onSignIn:_signIn,
          onReload:isWebPlatform&&!_sync.lastSyncOk&&_sync.lastServerContact!=null&&browserOnline?reloadApp:null,
          onEnableNotifications:_notificationsBanner?_enableNotifications:null,
          onDismissNotifications:()=>setState(()=>_notificationsDismissed=true),
          webUpdateChange:versionChange(appVersionFull,_servedVersion),webUpdateBuilds:'$appBuild → ${_servedBuild??'?'}',
          onWebUpdate:_webUpdate?()async{await widget.store.setPreference(_expectedVersionKey,_servedVersion??_servedBuild);await reloadFresh();}:null);
    final graphBanner=_graphs.pendingMobileBytes!=null&&!_graphs.downloading?Material(color:Theme.of(context).colorScheme.secondaryContainer,child:Padding(
          padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),
          child:Row(children:[const Icon(Icons.alt_route,size:18),const SizedBox(width:8),
            Expanded(child:Text(S.t('graph.mobile',{'mb':(_graphs.pendingMobileBytes!/1048576).toStringAsFixed(1)}),style:Theme.of(context).textTheme.bodySmall)),
            OutlinedButton(onPressed:()=>_graphs.check(allowMobile:true),child:Text(S.t('graph.download'))),
          ]))):null;
    // Phone, Carte tab, nothing above the map: full screen.
    final fullBleed=compact&&_tab==0&&sosAlert==null&&!banners.visible&&graphBanner==null;
    return PopScope(
      // Phone: Back first returns to the Carte tab, then leaves the application.
      // A panel over the map is closed first (31 Oct 2026).
      canPop:!compact||(_tab==0&&!_mapPanelOpen&&!_drawing.selectMode&&!_drawing.hasSelection&&_pickPoint==null),
      onPopInvokedWithResult:(didPop,_){if(didPop)return;if(_pickPoint!=null){_cancelPick();}else if(_drawing.selectMode||_drawing.hasSelection){_drawing.endSelection();}else if(_mapPanelOpen){_escapePanel();}else if(_tab!=0){_goTab(0);}},
      child:Scaffold(
      extendBody:fullBleed,
      body:SafeArea(top:!fullBleed,bottom:false,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        ?sosAlert,
        banners,
        ?graphBanner,
        Expanded(child:IndexedStack(index:compact?_tab:0,children:[_withDrawingShortcuts(Row(children:[
        // Computer: rail on the left (mock-up V2).
        if(!compact)_Rail(messages:messagesButton,actions:rail,bottom:railBottom,onMap:showMap,mapSelected:_deskPage==null&&_chatPeer==null&&!_showPanel&&!_showReferencePanel&&!_showRoutesPanel&&!_showResection),
        // Computer: Messages, Fichiers, APRS… open beside the rail, which
        // stays visible (« rail toujours visible », 28 Oct 2026).
        Expanded(child:IndexedStack(index:!compact&&_deskPage!=null?1:0,sizing:StackFit.expand,children:[Stack(fit:StackFit.expand,children:[Row(children:[
        if(!fullPanel&&_showResection&&_pickPoint==null)_resectionPanel(panelWidth(380)),
        if(_chatPeer!=null)chatSidePanel(width:panelWidth(420),child:MessagesPage(key:ValueKey('chat-$_chatPeer'),api:widget.api,eventId:widget.eventId,
          actorId:widget.deviceId,sync:_sync,store:widget.store,initialPeer:_chatPeer,onClose:()=>setState(()=>_chatPeer=null))),
        if(!fullPanel&&_showRoutesPanel)SizedBox(width:panelWidth(360),child:Material(elevation:3,child:routesPanel())),
        // Reference: the detailed sheet of a high point or a relay only;
        // filters by the chips, search by the search bar.
        if(_showReferencePanel&&_selectedReference!=null)SizedBox(width:panelWidth(355),child:Material(elevation:3,child:Builder(builder:(context){final r=_selectedReference!;return SingleChildScrollView(padding:const EdgeInsets.fromLTRB(14,8,6,14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Icon(r.isHighPoint?Icons.terrain:Icons.cell_tower,color:r.isHighPoint?Colors.indigo:Colors.deepOrange),const SizedBox(width:8),
              Expanded(child:Text(r.name,style:Theme.of(context).textTheme.titleMedium)),
              IconButton(tooltip:S.t('common.close'),onPressed:()=>setState((){_showReferencePanel=false;_selectedReference=null;}),icon:const Icon(Icons.close)),
            ]),
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
          ]));}))),
        // Computer: « Équipes » panel next to the map (list and nearby).
        if(_showPanel&&!compact)SizedBox(width:panelWidth(320),child:Material(elevation:3,child:_teams(sorted,screen:false))),
        Expanded(child:Stack(key:_mapKey,children:[mapBottomMargin(context,fullBleed:fullBleed,child:MouseRegion(onHover:_aimHover,opaque:false,child:FlutterMap(mapController:_map,options:MapOptions(
          initialCenter:_savedView==null?const LatLng(48.8566,2.3522):LatLng(_savedView.lat,_savedView.lon),initialZoom:_savedView?.zoom??11,maxZoom:20,onTap:_onMapTap,
          onPositionChanged:(camera,_)=>_onCameraChanged(camera),
          onLongPress:(_,point)=>_onLongPress(point,gesture:true),
          onSecondaryTap:(_,point){if(_aim!=null){_cancelAim();}else{_onLongPress(point,gesture:true);}},
          onMapEvent:_onMapEvent,
          onMapReady:(){if(mounted){_onCameraChanged(_map.camera);setState((){});}},
          // Rotation off: drawn arrows and handles assume north up.
          // Drag off while editing so handle and freehand gestures reach the shapes.
          interactionOptions:InteractionOptions(flags:InteractiveFlag.all&~InteractiveFlag.rotate&(_drawing.locksMapDrag?~InteractiveFlag.drag:~0)),
        ),children:[
          // Night: street maps darkened; aerial photos stay as they are.
          TileLayer(key:ValueKey('$_tileUrl|${_darkTiles(context)}'),urlTemplate:_tileUrl,userAgentPackageName:'org.sarcade.app',maxZoom:_basemap.maxZoom.toDouble(),
            tileBuilder:_darkTiles(context)?darkModeTileBuilder:null),
          if(traced.isNotEmpty)_faded('traces',PolylineLayer(polylines:_traces.polylines(traced,windowMin:_traceWindow))),
          if(_trace.length>1)PolylineLayer(polylines:_traceSegments().map((segment)=>Polyline(points:segment.map((p)=>LatLng(p.lat,p.lon)).toList(),strokeWidth:4,color:Theme.of(context).colorScheme.secondary)).toList()),
          // Reference sites below the drawn objects, grouped when zoomed out.
          if(_showHighPoints)_faded('high',ReferenceClusterLayer(sites:_references.values.where((r)=>r.isHighPoint).toList(),onSelect:_selectReference)),
          if(_showRelays)_faded('relay',ReferenceClusterLayer(sites:_references.values.where((r)=>r.isRelay).toList(),onSelect:_selectReference)),
          if(_showDrawings)..._fadedAll('draw',buildDrawingLayers(_drawing)),
          if(_showBearings||_bearings.taking||_adjusting!=null)..._fadedAll('brg',buildBearingLayers(bearings:_showBearings?_bearings.all.where((b)=>b.id!=_adjusting?.id&&b.id!=_aim?.editing?.id):const <Bearing>[],draft:_bearingDraft()??_adjusting,byOperator:_brgByOperator,hits:_bearingHits,
            onTapBearing:_showBearingSheet,onTapZone:(c,_)=>_onLongPress(c))),
          if(_aim!=null)...buildAimLayers(_aim!,Color(searchColor(_brgSearch))),
          ..._variantLayers(),
          ...buildRouteLayers(_routes,selectedRouteId:_selectedRouteId,itinerary:_nav.itinerary?.geometry??const [],draftClosure:_closureDraft,
            lineHits:_routeHits,onWaypointTap:(w)=>unawaited(_openWaypoint(w))),
          if(_showOrders)...buildMoveOrderLayers(isPco(widget.deviceId)?_moveOrders:[?_myOrder],_positionOf,_showMoveOrder),
          ...buildMeasureLayers(_measure,_coordFormat),
          ..._resectionLayers(),
          if(_showPois)_faded('poi',PoiClusterLayer(pois:_pois.values.toList(),onTap:(p)=>unawaited(_openPoi(p)))),
          _faded('aprs',MarkerLayer(markers:[...onMap.where(_isFixed).map(_fixedMarker),..._stationMarkers(onMap.where((p)=>p.isAprs&&!_isFixed(p)).toList())])),
          _faded('ops',MarkerLayer(markers:_stationMarkers(onMap.where((p)=>!p.isAprs).toList()))),
          if(_me!=null)MarkerLayer(markers:[Marker(point:_me!,width:22,height:22,child:GestureDetector(key:const ValueKey('me-dot'),
            onTap:()=>openMyPositionInfo(context,location:_location,places:_places,fallback:_me,onSendMessage:_sendText),
            child:Container(decoration:BoxDecoration(color:Colors.blue,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:3),boxShadow:const [BoxShadow(blurRadius:4,color:Colors.black26)]))))]),
          if(_trace.isNotEmpty)MarkerLayer(markers:[for(final t in _trace)Marker(point:LatLng(t.lat,t.lon),width:8,height:8,
            child:Container(decoration:BoxDecoration(color:Theme.of(context).colorScheme.secondary,shape:BoxShape.circle)))]),
          if(_scrub!=null)MarkerLayer(markers:[Marker(point:LatLng(_scrub!.lat,_scrub!.lon),width:22,height:22,
            child:Container(decoration:BoxDecoration(color:Theme.of(context).colorScheme.onSecondaryContainer,shape:BoxShape.circle,border:Border.all(color:Theme.of(context).colorScheme.secondary,width:3))))]),
          if(_searchPin!=null)MarkerLayer(markers:[Marker(point:_searchPin!,width:44,height:44,alignment:Alignment.topCenter,
            child:GestureDetector(onTap:()=>_onLongPress(_searchPin!),child:const Icon(Icons.location_on,color:Colors.red,size:44)))]),
          buildHandleLayer(_drawing,_globalToLatLng),
          // ⓘ with the licence notice of the base map: on the left, under the
          // scale, never under SOS (revue d'ergonomie n° 3).
          SafeArea(child:Padding(padding:EdgeInsets.only(bottom:compact?mapAttributionLift:0),
            child:RichAttributionWidget(alignment:AttributionAlignment.bottomLeft,
              attributions:[TextSourceAttribution(_basemap.attribution.isEmpty?widget.tileAttribution:_basemap.attribution)]))),
        ]))),
        if(_drawing.tool==FeatureKind.freehand)Positioned.fill(child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onPanStart:_onFreehandStart,onPanUpdate:_onFreehandUpdate,onPanEnd:_onFreehandEnd,
          child:CustomPaint(painter:_StrokePainter(_stroke,Color(_drawing.color),_drawing.strokeWidth)),
        )),
        if(_rectSelecting)Positioned.fill(child:SelectionRectOverlay(onRect:_onSelectionRect,onTap:_onSelectionTap,
          onMoveStart:_shiftDown?null:_onSelectionMoveStart,onMove:_shiftDown?null:_onSelectionMove,onWheel:_onSelectionWheel)),
        ShiftWatcher(onChanged:(v){if(mounted)setState(()=>_shiftDown=v);}),
        // Phone (card « Téléphone, carte en portrait », 1 h 32): the map goes
        // under the status bar and the floating tab bar; buttons stay in
        // the safe area.
        Positioned.fill(child:SafeArea(left:false,right:false,child:Stack(children:[
        // Scale first: behind every panel, never over a button (decision of
        // 30 Oct 2026, 16 h 25; revue n° 14, 18, 31); above the ⓘ.
        Positioned(left:16,bottom:mapScaleBottom(compact:compact),child:IgnorePointer(child:_scaleBar())),
        if(_inDistress)Positioned(top:8,left:8,right:8,child:Align(alignment:Alignment.topCenter,child:Material(color:Theme.of(context).colorScheme.error,
          borderRadius:BorderRadius.circular(16),child:InkWell(borderRadius:BorderRadius.circular(16),onTap:_distress,child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
            child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.sos,color:Theme.of(context).colorScheme.onError),const SizedBox(width:8),
              Text(S.t('distress.active'),style:TextStyle(color:Theme.of(context).colorScheme.onError,fontWeight:FontWeight.w700))]))))))
        else if(_pickPoint!=null)Positioned(top:8,left:8,right:8,child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),
          child:Container(padding:const EdgeInsets.fromLTRB(14,6,6,6),decoration:glass(context,border:Theme.of(context).colorScheme.primary),child:Row(children:[
            Icon(Icons.touch_app_outlined,color:Theme.of(context).colorScheme.primary),const SizedBox(width:10),
            Expanded(child:Text(_pickHint??'',style:const TextStyle(fontWeight:FontWeight.w600))),
            TextButton(onPressed:_cancelPick,child:Text(S.t('common.cancel'))),
          ])))))
        else if(_adjusting!=null)Positioned(top:8,left:8,right:8,child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:_adjustBanner())))
        else if(_bearings.taking)Positioned(top:8,left:8,right:8,child:Align(alignment:Alignment.topCenter,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:_bearingHud())))
        else Positioned(top:8,left:8,right:8,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          // The drawing button stays in place and toggles the toolbar
          // (request of 23 October 2026: closing it after a tap by mistake
          // meant reaching the small cross at the far right). Hidden in
          // follow mode (navigation variants), like the toolbar before.
          // One line, everything centred (card « Carte web, barre du haut,
          // finitions », 30 Oct 2026, 1 h 02): pills 40 px, buttons 48 px.
          // Top-aligned (revue n° 9): the results of the search open below
          // without moving the pencil and the link pill.
          if(!_follow)Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            _fab('drawing-tools',_drawingTools?S.t('draw.close'):S.t('draw.open'),Icon(_drawingTools?Icons.draw:Icons.draw_outlined),_toggleDrawingTools,
              background:_drawingTools?Theme.of(context).colorScheme.primary:null,
              foreground:_drawingTools?Theme.of(context).colorScheme.onPrimary:null),
            if(_drawingTools)...[
              const SizedBox(width:8),
              // Hidden while an object is edited: its card stays visible (13 h 25).
              if(_drawing.selection.isEmpty)Flexible(child:DrawingToolbar(controller:_drawing,onClose:_toggleDrawingTools)),
            ]else...[
              const SizedBox(width:8),
              // Computer (29 Oct 2026): « Suivi de position » right after the
              // search; the weather pill against the right edge, same margin
              // as the drawing button (card « Carte web, pastille météo +
              // liaison collée au bord droit », 30 Oct 2026): one flexible
              // child only, so no free space is left after the pill.
              Expanded(child:Row(children:[
                Flexible(child:MapSearchBar(items:_searchables,addresses:_searchAddresses,near:_mapCentre,onPick:_onSearchPick)),
                if(!compact)...[const SizedBox(width:8),_trackingBadge()],
              ])),
              const SizedBox(width:8),
              withId('link.map',_linkWeatherPill()),
            ],
          ]),
          // Phone: filters in one button; computer: chips visible.
          if(!_drawingTools)Padding(padding:const EdgeInsets.only(top:8),child:Wrap(spacing:8,runSpacing:8,children:[?_staleBanner(),?_orderBanner()])),
          if(_drawing.isDrawing)Padding(padding:const EdgeInsets.only(top:8),child:DraftBar(controller:_drawing)),
          if(_drawing.selectMode&&!_drawing.hasSelection)Padding(padding:const EdgeInsets.only(top:8),child:SelectionHint(controller:_drawing)),
          if(_drawing.isMulti)Padding(padding:const EdgeInsets.only(top:8),child:MultiSelectionBar(controller:_drawing,onExport:(f)=>_exportGeoJson(only:_drawing.selection,format:f))),
          if(_drawing.selected!=null)Padding(padding:const EdgeInsets.only(top:8),child:SelectionBar(controller:_drawing,onEditLabel:_editSelectedLabel,canFence:isPco(widget.deviceId))),
          if(_drawingClosure)Padding(padding:const EdgeInsets.only(top:8),child:Card(child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.block,color:Colors.red),const SizedBox(width:8),
            Flexible(child:Text(S.t('closures.drawHelp'))),
            OutlinedButton(onPressed:()=>setState((){_drawingClosure=false;_closureDraft.clear();}),child:Text(S.t('closures.cancel'))),
            FilledButton(onPressed:_finishClosure,child:Text(S.t('closures.finish'))),
          ])))),
        ])),
        // Phone, points added to an itinerary: compact bar at the bottom.
        if(routeEntry!=null)Positioned(left:12,right:12,bottom:12,child:RouteEntryBar(controller:_routes,route:routeEntry,
          onDone:()=>setState(()=>_drawingRouteId=null))),
        // Right column with SOS at its bottom (30 Oct 2026, 3 h 05).
        mapColumnPlacement(compact:compact,taking:_bearings.taking,card:selected!=null,bottom:compact?60:24,
          panel:_measure.target!=null||_nav.state!=NavState.idle||_nav.notice!=null,
          rightSheet:!compact&&_bearings.taking&&_aim!=null?bearingSheetWidth:0,child:_mapButtons()),
        // Phone: « Suivi actif » just above the tab bar.
        if(compact&&!_bearings.taking&&selected==null)Positioned(left:12,bottom:12,child:_trackingBadge()),
        if(_bearings.taking&&_aim!=null)Positioned(right:12,bottom:16,width:bearingSheetWidth,child:_bearingTakeSheet())
        else if(_bearings.taking)Positioned(left:0,right:0,bottom:16,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:_bearingTakeSheet()))))
        else if(selected!=null)Positioned(left:12,right:compact?12:null,bottom:compact?12:24,
          child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:_stationSheet(selected))),
        Positioned(left:0,right:0,bottom:compact?60:72,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Column(mainAxisSize:MainAxisSize.min,children:[
          MeasureCard(m:_measure,format:_coordFormat,onSavePoi:_savePoi,onSendMessage:_sendMeasure,
            onFit:(){final o=_measure.origin,t=_measure.target;if(t!=null)_fitPoints([?o?.point,t]);},
            onOpenElsewhere:(){final t=_measure.target;if(t!=null)_openElsewhere(t,_measure.targetLabel);},
            onChooseOrigin:_chooseOrigin,onDeclination:_editDeclination,mgrsDigits:_mgrsDigits,
            onMgrsDigits:(d) async {await widget.store.setPreference('mgrs_digits','$d');if(mounted)setState((){});},
            onFormat:(f) async {await widget.store.setPreference('coord_format',f.name);if(mounted)setState((){});}),
          NavigationCard(nav:_nav,following:_follow,onRecentre:()=>_setFollow(true),
            onOpenIn:(){final d=_nav.destination;if(d!=null)unawaited(_openElsewhere(d,_nav.label));},
            // No engine on the server and no road graph here: one touch (31 Oct 2026).
            onDownloadGraph:_graphs.graph==null?()=>unawaited(_graphs.check(allowMobile:true)):null,
            graphBytes:_graphs.pendingMobileBytes,graphDownloading:_graphs.downloading,
            rotate:_phoneOrTablet?null:_followRotates,
            onRotate:_phoneOrTablet?null:(v) async {
              await widget.store.setPreference('nav_rotate_desktop',v?'1':null);
              _lastFollowRotation=null;
              if(_follow)_applyFollow();
              if(mounted)setState((){});
            }),
        ])))),
        ]))),
      ]))
      
        ]),
        if(fullPanel&&_showResection&&_pickPoint==null)phonePanel(_resectionPanel(screenWidth)),
        if(fullPanel&&_showRoutesPanel&&routeEntry==null)phonePanel(routesPanel()),
        ]),
        _deskPage??const SizedBox.shrink(),
        ])),
])),
        // Phone: the other tabs, built at their first visit then kept.
        if(compact)...[
          _builtTabs.contains(1)?MessagesPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId,sync:_sync,store:widget.store,active:_tab==1,navigator:_messagesNav):const SizedBox.shrink(),
          _builtTabs.contains(2)?_teams(sorted,screen:true):const SizedBox.shrink(),
          _builtTabs.contains(3)?ToolsPage(items:_toolItems()):const SizedBox.shrink(),
          _builtTabs.contains(4)?_moreScreen(more):const SizedBox.shrink(),
        ],
      ])),
      ])),
      // Phone: tab bar always visible, each tab a real screen.
      bottomNavigationBar:compact?_TabBar(index:_tab,messagesIcon:_messagesIcon(),onSelect:(i)=>i==1?_openMessages(fromButton:true):i==0?_showMapOnly():_goTab(i),moreAlert:diagnosticsAlert()):null,
    ));
  }
}

/// One action of the rail (computer) or of the « Plus » sheet (phone).
class _RailAction {
  final IconData icon; final String label; final VoidCallback onTap; final bool selected;
  /// Red dot: a problem waits in the Diagnostic (Paramètres).
  final bool alert;
  /// Test identifier (`nav.<id>` in the rail, `more.<id>` on the phone).
  final String id;
  const _RailAction(this.icon,this.label,this.onTap,{this.selected=false,this.alert=false,this.id=''});
}

/// Computer: vertical rail on the left, 9 entries (note « Navigation et
/// menus simplifiés »): Carte, Messages, then [actions], « Plus » last.
class _Rail extends StatelessWidget {
  final Widget messages; final List<_RailAction> actions; final _RailAction? bottom; final VoidCallback onMap; final bool mapSelected;
  const _Rail({required this.messages,required this.actions,required this.onMap,required this.mapSelected,this.bottom});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    Widget button(IconData icon,String label,VoidCallback onTap,{bool selected=false,bool alert=false,String id=''})=>Padding(padding:const EdgeInsets.symmetric(vertical:2),
      child:withId('nav.$id',IconButton(tooltip:label,onPressed:onTap,isSelected:selected,
        style:IconButton.styleFrom(fixedSize:const Size(48,48),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
          backgroundColor:selected?scheme.primaryContainer:null,foregroundColor:selected?scheme.primary:scheme.onSurfaceVariant),
        icon:Badge(isLabelVisible:alert,smallSize:10,child:Icon(icon)))));
    return Container(width:72,margin:const EdgeInsets.fromLTRB(8,8,0,8),decoration:glass(context),
      child:Column(children:[
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(vertical:8),child:Column(children:[
          button(Icons.map_outlined,S.t('tabs.map'),onMap,selected:mapSelected,id:'map'),
          Padding(padding:const EdgeInsets.symmetric(vertical:2),child:withId('nav.messages',messages)),
          for(final a in actions)button(a.icon,a.label,a.onTap,selected:a.selected,id:a.id),
        ]))),
        if(bottom!=null)...[
          const Divider(height:1,indent:14,endIndent:14),
          Padding(padding:const EdgeInsets.symmetric(vertical:6),child:button(bottom!.icon,bottom!.label,bottom!.onTap,selected:bottom!.selected,alert:bottom!.alert,id:bottom!.id)),
        ],
      ]));
  }
}

/// Phone: tab bar always visible; each tab is a real screen.
class _TabBar extends StatelessWidget {
  final int index; final Widget messagesIcon; final ValueChanged<int> onSelect; final bool moreAlert;
  const _TabBar({required this.index,required this.messagesIcon,required this.onSelect,this.moreAlert=false});
  @override Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    const ids=['map','messages','teams','tools','more'];
    Widget tab(int i,Widget icon,String label,{String? tooltip})=>Expanded(child:Tooltip(message:tooltip??label,excludeFromSemantics:true,child:InkWell(
      onTap:()=>onSelect(i),borderRadius:BorderRadius.circular(28),
      child:Semantics(identifier:'nav.${ids[i]}',button:true,selected:index==i,label:tooltip??label,excludeSemantics:true,child:Container(height:60,
        decoration:BoxDecoration(color:index==i?scheme.primaryContainer:null,borderRadius:BorderRadius.circular(28)),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          IconTheme(data:IconThemeData(color:index==i?scheme.primary:scheme.onSurfaceVariant),child:icon),
          const SizedBox(height:2),
          Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:13,fontWeight:index==i?FontWeight.w700:FontWeight.w500,
            color:index==i?scheme.primary:scheme.onSurfaceVariant)),
        ]))))));
    // Floating and semi-transparent over the full-screen map (30 Oct 2026).
    return SafeArea(top:false,child:Container(height:72,margin:const EdgeInsets.fromLTRB(8,4,8,8),padding:const EdgeInsets.symmetric(horizontal:4),
      decoration:glass(context,radius:34).copyWith(color:scheme.surface.withValues(alpha:0.78)),
      child:Row(children:[
        tab(0,const Icon(Icons.map_outlined),S.t('tabs.map')),
        // Same tooltip as before: « Messages » (tests and screen readers).
        tab(1,messagesIcon,S.t('tabs.messages'),tooltip:S.t('map.messages')),
        tab(2,const Icon(Icons.groups_outlined),S.t('tabs.teams')),
        tab(3,const Icon(Icons.build_outlined),S.t('tools.title')),
        tab(4,Badge(isLabelVisible:moreAlert,smallSize:10,child:const Icon(Icons.more_horiz)),S.t('tabs.more')),
      ])));
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

/// Button kept pressed 2 s before acting (distress: no stray touch).
class _HoldButton extends StatefulWidget {
  final String label; final VoidCallback onDone;
  const _HoldButton({required this.label,required this.onDone});
  @override State<_HoldButton> createState()=>_HoldButtonState();
}
class _HoldButtonState extends State<_HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c=AnimationController(vsync:this,duration:const Duration(seconds:2))
    ..addStatusListener((s){if(s==AnimationStatus.completed)widget.onDone();});
  @override void dispose(){_c.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return GestureDetector(onTapDown:(_)=>_c.forward(from:0),onTapUp:(_)=>_c.reset(),onTapCancel:()=>_c.reset(),
      child:AnimatedBuilder(animation:_c,builder:(_,_)=>Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),gradient:LinearGradient(colors:[s.error,s.error,s.errorContainer,s.errorContainer],
          stops:[0,_c.value,_c.value,1])),
        child:Text(widget.label,style:TextStyle(color:s.onError,fontWeight:FontWeight.w700)))));
  }
}

/// « Opérateurs (4) · Stations (2) » when fixed stations are listed too
/// (revue d'ergonomie n° 42).
String operatorsTitle(int operators,int stations)=>stations==0?S.t('operators.title',{'n':operators})
  :S.t('operators.titleStations',{'n':operators,'m':stations});

/// True when a window covers or flanks the map.
bool mapPanelOpen({required bool teams,required bool reference,required bool routes,required bool resection,required bool chat,required bool desk})=>
  teams||reference||routes||resection||chat||desk;
