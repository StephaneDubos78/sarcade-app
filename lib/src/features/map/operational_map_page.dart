import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../models/poi.dart';
import '../../models/message.dart';
import '../../models/position.dart';
import '../messages/messages_page.dart';
import '../logbook/logbook_page.dart';
import '../../services/notification_service.dart';
import '../../services/location_service.dart';
import '../../services/realtime_service.dart';
import '../../services/sarcade_api.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';

class OperationalMapPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,deviceId,tileUrl,tileAttribution; final LocalStore store;
  const OperationalMapPage({super.key,required this.api,required this.eventId,required this.deviceId,required this.store,required this.tileUrl,required this.tileAttribution});
  @override State<OperationalMapPage> createState()=>_OperationalMapPageState();
}

class _OperationalMapPageState extends State<OperationalMapPage> {
  final _map=MapController(); final _realtime=RealtimeService(); final _location=LocationService(); final _notifications=NotificationService(); final _uuid=const Uuid();
  final Map<String,SarcadePosition> _positions={}; final Map<String,SarcadePoi> _pois={};
  StreamSubscription? _rtSub,_gpsSub; String _status='Connexion…'; bool _tracking=false; bool _showPanel=true; String? _selectedDevice; List<SarcadePosition> _trace=[]; bool _traceLoading=false; late final OfflineSyncService _sync;

  @override void initState(){super.initState();_notifications.initialize();_sync=OfflineSyncService(api:widget.api,store:widget.store,eventId:widget.eventId);_loadLocal();_sync.start();_start();}
  bool _validPosition(SarcadePosition p){
    final t=p.time.toUtc(), now=DateTime.now().toUtc();
    return t.isAfter(DateTime.utc(2020)) && t.isBefore(now.add(const Duration(days:1)));
  }
  void _loadLocal(){for(final j in widget.store.positions()){final p=SarcadePosition.fromJson(j);if(p.eventId==widget.eventId&&_validPosition(p))_positions[p.deviceId]=p;}for(final j in widget.store.pois()){final p=SarcadePoi.fromJson(j);if(p.eventId==widget.eventId)_pois[p.id]=p;}}
  Future<void> _start() async {
    try {
      final data=await Future.wait([widget.api.latestPositions(widget.eventId),widget.api.pois(widget.eventId)]);
      for(final p in data[0] as List<SarcadePosition>){if(_validPosition(p)){_positions[p.deviceId]=p;widget.store.cachePosition(p.toJson());}}
      for(final p in data[1] as List<SarcadePoi>){_pois[p.id]=p;}
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

  @override void dispose(){_rtSub?.cancel();_gpsSub?.cancel();_sync.dispose();_realtime.dispose();widget.api.close();super.dispose();}

  @override Widget build(BuildContext context){
    final sorted=_positions.values.toList()..sort((a,b)=>a.deviceId.compareTo(b.deviceId));
    final markers=<Marker>[
      ...sorted.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:130,height:62,alignment:Alignment.topCenter,child:GestureDetector(onTap:()=>_select(p),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.person_pin_circle,size:38,color:p.deviceId==widget.deviceId?Colors.orange:(_selectedDevice==p.deviceId?Colors.deepPurple:Colors.blue)),Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(5),boxShadow:const [BoxShadow(blurRadius:2)]),child:Text(p.deviceId,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600)))])))),
      ..._pois.values.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:40,height:40,child:Tooltip(message:p.label??p.kind,child:const Icon(Icons.location_on,size:38,color:Colors.red)))),
    ];
    final selected=_selectedDevice==null?null:_positions[_selectedDevice];
    return Scaffold(
      appBar:AppBar(title:const Text('SARCADE'),actions:[IconButton(tooltip:'Synchroniser',onPressed:() async {await _sync.syncNow();if(mounted)setState((){});},icon:const Icon(Icons.sync)),IconButton(tooltip:'Cadrer les opérateurs',onPressed:_fitOperators,icon:const Icon(Icons.center_focus_strong)),IconButton(tooltip:'Opérateurs',onPressed:()=>setState(()=>_showPanel=!_showPanel),icon:const Icon(Icons.groups)),IconButton(tooltip:'Messages',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(eventId:widget.eventId,actorId:widget.deviceId,sync:_sync,store:widget.store))),icon:Badge(label:Text('${widget.store.pendingCount()}'),child:const Icon(Icons.message))),IconButton(tooltip:'Main courante',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LogbookPage(api:widget.api,eventId:widget.eventId))),icon:const Icon(Icons.receipt_long)),Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Center(child:Text('$_status · ${widget.store.pendingCount()} attente')))]),
      body:Row(children:[
        if(_showPanel)SizedBox(width:285,child:Material(elevation:3,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.all(14),child:Text('Opérateurs (${sorted.length})',style:Theme.of(context).textTheme.titleMedium)),
          Expanded(child:ListView(children:sorted.map((p)=>ListTile(selected:_selectedDevice==p.deviceId,leading:Icon(Icons.circle,size:13,color:DateTime.now().toUtc().difference(p.time.toUtc()).inMinutes<5?Colors.green:Colors.grey),title:Text(p.deviceId),subtitle:Text('Dernière position : ${_age(p.time)}'),onTap:()=>_select(p))).toList())),
          if(selected!=null)Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(border:Border(top:BorderSide(color:Theme.of(context).dividerColor))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(selected.deviceId,style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),Text('Lat : ${selected.lat.toStringAsFixed(6)}'),Text('Lon : ${selected.lon.toStringAsFixed(6)}'),Text('Précision : ${selected.accuracyM?.toStringAsFixed(1)??'-'} m'),Text('Heure : ${selected.time.toLocal()}'),Text(_traceLoading?'Trace : chargement…':'Trace : ${_trace.length} points')]))
        ]))),
        Expanded(child:FlutterMap(mapController:_map,options:const MapOptions(initialCenter:LatLng(48.8566,2.3522),initialZoom:11,maxZoom:20),children:[
          TileLayer(urlTemplate:widget.tileUrl,userAgentPackageName:'org.sarcade.app',maxZoom:19),
          if(_trace.length>1)PolylineLayer(polylines:_traceSegments().map((segment)=>Polyline(points:segment.map((p)=>LatLng(p.lat,p.lon)).toList(),strokeWidth:4,color:Colors.deepPurple)).toList()),
          MarkerLayer(markers:markers),
          RichAttributionWidget(attributions:[TextSourceAttribution(widget.tileAttribution)]),
        ]))
      ]),
      floatingActionButton:FloatingActionButton.extended(onPressed:_toggleTracking,icon:Icon(_tracking?Icons.location_off:Icons.my_location),label:Text(_tracking?'Arrêter GPS':'Partager position')),
    );
  }
}
