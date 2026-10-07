import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
import 'drawing/map_feature.dart';
import '../../services/notification_service.dart';
import '../../services/location_service.dart';
import '../../services/realtime_service.dart';
import '../../services/sarcade_api.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';

class OperationalMapPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,deviceId,tileUrl,tileAttribution; final LocalStore store; final VoidCallback? onSettings;
  const OperationalMapPage({super.key,required this.api,required this.eventId,required this.deviceId,required this.store,required this.tileUrl,required this.tileAttribution,this.onSettings});
  @override State<OperationalMapPage> createState()=>_OperationalMapPageState();
}

class _OperationalMapPageState extends State<OperationalMapPage> {
  final _map=MapController(); final _realtime=RealtimeService(); final _location=LocationService(); final _notifications=NotificationService(); final _uuid=const Uuid();
  final Map<String,SarcadePosition> _positions={}; final Map<String,SarcadePoi> _pois={}; final Map<String,ReferenceSite> _references={};
  StreamSubscription? _rtSub,_gpsSub; Timer? _syncUiTimer; String _status='Connexion…'; bool _tracking=false; bool _showPanel=true; bool _showReferencePanel=false; bool _showHighPoints=true; bool _showRelays=true; String _referenceQuery=''; String? _selectedDevice; ReferenceSite? _selectedReference; List<SarcadePosition> _trace=[]; bool _traceLoading=false; late final OfflineSyncService _sync; bool _layoutInitialized=false;
  late final DrawingController _drawing; bool _drawingTools=false; final _mapKey=GlobalKey();
  final List<Offset> _stroke=[];

  // Phones get the map full width: side panels start closed and open as overlays.
  static const _compactWidth=600.0;
  @override void didChangeDependencies(){super.didChangeDependencies();if(!_layoutInitialized){_layoutInitialized=true;if(MediaQuery.sizeOf(context).width<_compactWidth)_showPanel=false;}}

  @override void initState(){super.initState();_notifications.initialize();_sync=OfflineSyncService(api:widget.api,store:widget.store,eventId:widget.eventId);_initDrawing();_loadLocal();_sync.start();_syncUiTimer=Timer.periodic(const Duration(seconds:2),(_){if(mounted)setState((){});});_start();}
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
      _rtSub=_realtime.events.listen(_onRealtime,onError:(_){if(mounted)setState(()=>_status='Temps réel indisponible');});
      if(mounted){setState(()=>_status='Connecté');WidgetsBinding.instance.addPostFrameCallback((_)=>_fitOperators());}
    } catch(e){if(mounted)setState(()=>_status='Hors connexion');}
  }
  void _onRealtime(RealtimeEvent e){
    if(e.type=='position.updated'){final p=SarcadePosition.fromJson(e.data);if(_validPosition(p)){widget.store.cachePosition(p.toJson());if(mounted)setState((){_positions[p.deviceId]=p;if(_selectedDevice==p.deviceId)_trace.add(p);});}}
    if(e.type=='poi.created'){final p=SarcadePoi.fromJson(e.data);widget.store.cachePoi(e.data);setState(()=>_pois[p.id]=p);}
    if(e.type=='message.created'){_receiveMessage(e.data);}
    if(e.type=='ack.created'){widget.store.cacheAck(e.data);if(mounted)setState((){});}
  }

  Future<void> _receiveMessage(Map<String,dynamic> data) async {
    final m=SarcadeMessage.fromJson(data);
    await widget.store.cacheMessage(data);
    final addressed=m.recipientIds.isEmpty||m.recipientIds.contains('user:${widget.deviceId}')||m.recipientIds.contains(widget.deviceId);
    if(addressed && m.senderId!=widget.deviceId){
      final existing=widget.store.acks().map(SarcadeAck.fromJson).any((a)=>a.messageId==m.id&&a.actorId==widget.deviceId&&a.status=='received');
      if(!existing){
        final ack=SarcadeAck(id:_uuid.v4(),eventId:widget.eventId,messageId:m.id,actorId:widget.deviceId,status:'received',time:DateTime.now().toUtc());
        await widget.store.cacheAck(ack.toJson());
        await _sync.queue(objectId:ack.id,objectType:'ack',payload:ack.toJson());
      }
      await _notifications.message(title:'SARCADE · ${m.priority}',body:m.body,priority:m.priority);
    }
    if(mounted)setState((){});
  }

  Future<void> _toggleTracking() async {
    if(_tracking){await _gpsSub?.cancel();setState(()=>_tracking=false);return;}
    if(!await _location.ensurePermission()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Localisation non autorisée ou indisponible')));return;}
    _gpsSub=_location.positions().listen((g) async {
      final p=SarcadePosition(id:_uuid.v4(),eventId:widget.eventId,deviceId:widget.deviceId,lat:g.latitude,lon:g.longitude,time:g.timestamp,altM:g.altitude,accuracyM:g.accuracy,headingDeg:g.heading>=0?g.heading:null,speedMps:g.speed>=0?g.speed:null);
      await widget.store.cachePosition(p.toJson());
      if(mounted)setState(()=>_positions[widget.deviceId]=p);
      await _sync.queue(objectId:p.id,objectType:'position',payload:p.toJson());
    });
    setState(()=>_tracking=true);
  }
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
      if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Référentiel mis à jour : ${refs.length} éléments')));
    }catch(e){
      if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Mise à jour du référentiel impossible')));
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
      onSaved:(f)=>widget.store.saveMapFeature(f.toJson()),
      onDeleted:(id)=>widget.store.deleteMapFeature(id),
    );
    _drawing.addListener(_onDrawingChanged);
  }
  void _onDrawingChanged(){if(mounted)setState((){});}

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
    if(_drawing.isDrawing){
      if(_drawing.tool==FeatureKind.text){
        final text=await _askText(title:'Texte sur la carte',initial:'');
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
        TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
        FilledButton(onPressed:()=>Navigator.pop(context,controller.text),child:const Text('OK')),
      ],
    )).whenComplete(controller.dispose);
  }

  Future<void> _editSelectedLabel() async {
    final f=_drawing.selected;
    if(f==null)return;
    final text=await _askText(title:f.kind==FeatureKind.text?'Modifier le texte':'Nom de l’objet',initial:f.label);
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

  /// Exports the event's drawn objects as GeoJSON: a local copy on the device,
  /// and an upload to the event's shared files so the PCO receives it.
  Future<void> _exportGeoJson() async {
    final messenger=ScaffoldMessenger.of(context);
    final stamp=DateTime.now().toIso8601String().substring(0,16).replaceAll(RegExp(r'[:T]'),'-');
    final name='sarcade-objets-${widget.eventId}-$stamp.geojson'.replaceAll(RegExp(r'[\\/:*?"<>|]'),'_');
    final bytes=utf8.encode(const JsonEncoder.withIndent('  ').convert(featureCollection(_drawing.features)));
    String? localPath;
    try{
      final dir=await getApplicationDocumentsDirectory();
      localPath='${dir.path}${Platform.pathSeparator}$name';
      await File(localPath).writeAsBytes(bytes,flush:true);
    }catch(_){localPath=null;}
    var shared=false;
    try{await widget.api.uploadFile(widget.eventId,widget.deviceId,name,'application/geo+json',bytes);shared=true;}catch(_){}
    if(!mounted)return;
    final count=_drawing.features.length;
    messenger.showSnackBar(SnackBar(
      duration:const Duration(seconds:6),
      content:Text(shared?'$count objets exportés et partagés dans les fichiers de l’événement':localPath!=null?'$count objets exportés sur l’appareil, partage impossible hors connexion':'Export impossible'),
      action:localPath==null?null:SnackBarAction(label:'Ouvrir',onPressed:()=>OpenFilex.open(localPath!)),
    ));
  }

  @override void dispose(){_rtSub?.cancel();_gpsSub?.cancel();_syncUiTimer?.cancel();_sync.dispose();_realtime.dispose();_drawing.dispose();widget.api.close();super.dispose();}

  @override Widget build(BuildContext context){
    final sorted=_positions.values.toList()..sort((a,b)=>a.deviceId.compareTo(b.deviceId));
    final markers=<Marker>[
      ...sorted.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:130,height:62,alignment:Alignment.topCenter,child:GestureDetector(onTap:()=>_select(p),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.person_pin_circle,size:38,color:p.deviceId==widget.deviceId?Colors.orange:(_selectedDevice==p.deviceId?Colors.deepPurple:Colors.blue)),Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(5),boxShadow:const [BoxShadow(blurRadius:2)]),child:Text(p.deviceId,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600)))])))),
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
    void toggleReferences()=>setState((){_showReferencePanel=!_showReferencePanel;if(_showReferencePanel)_showPanel=false;});
    void openFiles()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>FilesPage(api:widget.api,eventId:widget.eventId,actorId:widget.deviceId)));
    void openLogbook()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LogbookPage(api:widget.api,eventId:widget.eventId)));
    final syncButton=IconButton(tooltip:'Synchroniser',onPressed:() async {await _sync.syncNow();if(mounted)setState((){});},icon:const Icon(Icons.sync));
    final messagesButton=IconButton(tooltip:'Messages',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(eventId:widget.eventId,actorId:widget.deviceId,sync:_sync,store:widget.store))),icon:Badge(label:Text('${widget.store.pendingCount()}'),child:const Icon(Icons.message)));
    return Scaffold(
      appBar:compact
        ? AppBar(
            titleSpacing:12,
            title:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[const Text('SARCADE'),Text('$_status · ${widget.store.pendingCount()} attente',style:Theme.of(context).textTheme.labelSmall,overflow:TextOverflow.ellipsis)]),
            actions:[
              syncButton,
              messagesButton,
              PopupMenuButton<String>(
                tooltip:'Menu',
                onSelected:(v){switch(v){case 'fit':_fitOperators();case 'operators':toggleOperators();case 'references':toggleReferences();case 'files':openFiles();case 'logbook':openLogbook();case 'settings':widget.onSettings?.call();}},
                itemBuilder:(_)=>[
                  const PopupMenuItem(value:'fit',child:ListTile(leading:Icon(Icons.center_focus_strong),title:Text('Cadrer les opérateurs'))),
                  const PopupMenuItem(value:'operators',child:ListTile(leading:Icon(Icons.groups),title:Text('Opérateurs'))),
                  const PopupMenuItem(value:'references',child:ListTile(leading:Icon(Icons.cell_tower),title:Text('Référentiel radio'))),
                  const PopupMenuItem(value:'files',child:ListTile(leading:Icon(Icons.folder_copy_outlined),title:Text('Fichiers'))),
                  const PopupMenuItem(value:'logbook',child:ListTile(leading:Icon(Icons.receipt_long),title:Text('Main courante'))),
                  if(widget.onSettings!=null)const PopupMenuItem(value:'settings',child:ListTile(leading:Icon(Icons.settings),title:Text('Paramètres'))),
                ],
              ),
            ])
        : AppBar(title:const Text('SARCADE'),actions:[syncButton,IconButton(tooltip:'Cadrer les opérateurs',onPressed:_fitOperators,icon:const Icon(Icons.center_focus_strong)),IconButton(tooltip:'Opérateurs',onPressed:toggleOperators,icon:const Icon(Icons.groups)),IconButton(tooltip:'Référentiel radio',onPressed:toggleReferences,icon:const Icon(Icons.cell_tower)),messagesButton,IconButton(tooltip:'Fichiers',onPressed:openFiles,icon:const Icon(Icons.folder_copy_outlined)),IconButton(tooltip:'Main courante',onPressed:openLogbook,icon:const Icon(Icons.receipt_long)),if(widget.onSettings!=null)IconButton(tooltip:'Paramètres',onPressed:widget.onSettings,icon:const Icon(Icons.settings)),Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Center(child:Text('$_status · ${widget.store.pendingCount()} attente')))]),
      body:Row(children:[
        if(_showReferencePanel)SizedBox(width:panelWidth(355),child:Material(elevation:3,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.fromLTRB(14,8,6,0),child:Row(children:[Expanded(child:Text('Référentiel radio (${_filteredReferences().length})',style:Theme.of(context).textTheme.titleMedium)),IconButton(tooltip:'Actualiser le référentiel',onPressed:()=>_refreshReferences(),icon:const Icon(Icons.refresh))])),
          Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Nom, indicatif, fréquence, mode…',isDense:true,border:OutlineInputBorder()),onChanged:(v)=>setState(()=>_referenceQuery=v))),
          Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Wrap(spacing:8,children:[
            FilterChip(label:const Text('Points hauts'),selected:_showHighPoints,onSelected:(v)=>setState(()=>_showHighPoints=v)),
            FilterChip(label:const Text('Relais'),selected:_showRelays,onSelected:(v)=>setState(()=>_showRelays=v)),
          ])),
          Expanded(child:ListView.builder(itemCount:_filteredReferences().length,itemBuilder:(context,index){final r=_filteredReferences()[index];return ListTile(selected:_selectedReference?.id==r.id,leading:Icon(r.isHighPoint?Icons.terrain:Icons.cell_tower,color:r.isHighPoint?Colors.indigo:Colors.deepOrange),title:Text(r.name),subtitle:Text(r.subtitle),onTap:()=>_selectReference(r));})),
          if(_selectedReference!=null)Builder(builder:(context){final r=_selectedReference!;return Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(border:Border(top:BorderSide(color:Theme.of(context).dividerColor))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(r.name,style:const TextStyle(fontWeight:FontWeight.bold)),
            if(r.callsign?.isNotEmpty==true)Text('Indicatif : ${r.callsign}'),
            if(r.isHighPoint&&r.altM!=null)Text('Altitude : ${r.altM!.toStringAsFixed(0)} m'),
            if(r.subtype?.isNotEmpty==true)Text('Type : ${r.subtype}'),
            if(r.mode?.isNotEmpty==true)Text('Mode : ${r.mode}'),
            if(r.isRelay)Text('Entrée : ${_frequency(r.rxMhz)}'),
            if(r.isRelay)Text('Sortie : ${_frequency(r.txMhz)}'),
            if(r.ctcssRx?.isNotEmpty==true)Text('CTCSS entrée : ${r.ctcssRx}'),
            if(r.ctcssTx?.isNotEmpty==true)Text('CTCSS sortie : ${r.ctcssTx}'),
            if(r.access?.isNotEmpty==true)Text('Accès : ${r.access}'),
            if(r.clearance?.isNotEmpty==true)Text('Dégagement : ${r.clearance}'),
            if(r.verifiedAt?.isNotEmpty==true)Text('Vérifié : ${r.verifiedAt}'),
          ]));}),
        ]))),
        if(_showPanel)SizedBox(width:panelWidth(285),child:Material(elevation:3,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.all(14),child:Text('Opérateurs (${sorted.length})',style:Theme.of(context).textTheme.titleMedium)),
          Expanded(child:ListView(children:sorted.map((p)=>ListTile(selected:_selectedDevice==p.deviceId,leading:Icon(Icons.circle,size:13,color:DateTime.now().toUtc().difference(p.time.toUtc()).inMinutes<5?Colors.green:Colors.grey),title:Text(p.deviceId),subtitle:Text('Dernière position : ${_age(p.time)}'),onTap:()=>_select(p))).toList())),
          if(selected!=null)Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(border:Border(top:BorderSide(color:Theme.of(context).dividerColor))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(selected.deviceId,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('Lat : ${selected.lat.toStringAsFixed(6)}'),Text('Lon : ${selected.lon.toStringAsFixed(6)}'),Text('Précision : ${selected.accuracyM?.toStringAsFixed(1)??'-'} m'),Text('Heure : ${selected.time.toLocal()}'),Text(_traceLoading?'Trace : chargement…':'Trace : ${_trace.length} points')]))
        ]))),
        Expanded(child:Stack(key:_mapKey,children:[FlutterMap(mapController:_map,options:MapOptions(
          initialCenter:const LatLng(48.8566,2.3522),initialZoom:11,maxZoom:20,onTap:_onMapTap,
          // Rotation off: drawn arrows and handles assume north up.
          // Drag off while editing so handle and freehand gestures reach the shapes.
          interactionOptions:InteractionOptions(flags:InteractiveFlag.all&~InteractiveFlag.rotate&(_drawing.locksMapDrag?~InteractiveFlag.drag:~0)),
        ),children:[
          TileLayer(urlTemplate:widget.tileUrl,userAgentPackageName:'org.sarcade.app',maxZoom:19),
          if(_trace.length>1)PolylineLayer(polylines:_traceSegments().map((segment)=>Polyline(points:segment.map((p)=>LatLng(p.lat,p.lon)).toList(),strokeWidth:4,color:Colors.deepPurple)).toList()),
          ...buildDrawingLayers(_drawing),
          MarkerLayer(markers:markers),
          buildHandleLayer(_drawing,_globalToLatLng),
          RichAttributionWidget(attributions:[TextSourceAttribution(widget.tileAttribution)]),
        ]),
        if(_drawing.tool==FeatureKind.freehand)Positioned.fill(child:GestureDetector(
          behavior:HitTestBehavior.opaque,
          onPanStart:_onFreehandStart,onPanUpdate:_onFreehandUpdate,onPanEnd:_onFreehandEnd,
          child:CustomPaint(painter:_StrokePainter(_stroke,Color(_drawing.color),_drawing.strokeWidth)),
        )),
        Positioned(top:8,left:8,right:8,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(_drawingTools)DrawingToolbar(controller:_drawing,onExport:_exportGeoJson,onClose:(){_drawing.selectTool(null);setState(()=>_drawingTools=false);})
          else FloatingActionButton.small(heroTag:'drawing-tools',tooltip:'Dessiner sur la carte',onPressed:()=>setState(()=>_drawingTools=true),child:const Icon(Icons.draw_outlined)),
          if(_drawing.isDrawing)Padding(padding:const EdgeInsets.only(top:8),child:DraftBar(controller:_drawing)),
          if(_drawing.selected!=null)Padding(padding:const EdgeInsets.only(top:8),child:SelectionBar(controller:_drawing,onEditLabel:_editSelectedLabel)),
        ])),
      ]))
      ]),
      floatingActionButton:FloatingActionButton.extended(onPressed:_toggleTracking,icon:Icon(_tracking?Icons.location_off:Icons.my_location),label:Text(_tracking?'Arrêter GPS':'Partager position')),
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
