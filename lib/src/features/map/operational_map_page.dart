import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre/flutter_map_maplibre.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../models/poi.dart';
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
  final SarcadeApi api; final String eventId, deviceId; final LocalStore store;
  const OperationalMapPage({super.key,required this.api,required this.eventId,required this.deviceId,required this.store});
  @override State<OperationalMapPage> createState()=>_OperationalMapPageState();
}

class _OperationalMapPageState extends State<OperationalMapPage> {
  final _map=MapController(); final _realtime=RealtimeService(); final _location=LocationService(); final _notifications=NotificationService(); final _uuid=const Uuid();
  final Map<String,SarcadePosition> _positions={}; final Map<String,SarcadePoi> _pois={};
  StreamSubscription? _rtSub,_gpsSub; String _status='Connexion…'; bool _tracking=false; late final OfflineSyncService _sync;

  @override void initState(){super.initState();_notifications.initialize();_sync=OfflineSyncService(api:widget.api,store:widget.store,eventId:widget.eventId);_loadLocal();_sync.start();_start();}
  void _loadLocal(){for(final j in widget.store.positions()){final p=SarcadePosition.fromJson(j);_positions[p.deviceId]=p;}for(final j in widget.store.pois()){final p=SarcadePoi.fromJson(j);_pois[p.id]=p;}}
  Future<void> _start() async {
    try {
      final data=await Future.wait([widget.api.latestPositions(widget.eventId),widget.api.pois(widget.eventId)]);
      for(final p in data[0] as List<SarcadePosition>){_positions[p.deviceId]=p;widget.store.cachePosition(p.toJson());}
      for(final p in data[1] as List<SarcadePoi>){_pois[p.id]=p;}
      _realtime.connect(widget.api.websocketUri(widget.eventId));
      _rtSub=_realtime.events.listen(_onRealtime,onError:(_){if(mounted)setState(()=>_status='Temps réel indisponible');});
      if(mounted)setState(()=>_status='Connecté');
    } catch(e){if(mounted)setState(()=>_status='Hors connexion');}
  }
  void _onRealtime(RealtimeEvent e){
    if(e.type=='position.updated'){final p=SarcadePosition.fromJson(e.data);widget.store.cachePosition(p.toJson());setState(()=>_positions[p.deviceId]=p);}
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
  @override void dispose(){_rtSub?.cancel();_gpsSub?.cancel();_sync.dispose();_realtime.dispose();widget.api.close();super.dispose();}

  @override Widget build(BuildContext context){
    final markers=<Marker>[
      ..._positions.values.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:44,height:44,child:Tooltip(message:p.deviceId,child:Icon(Icons.person_pin_circle,size:40,color:p.deviceId==widget.deviceId?Colors.orange:Colors.blue)))),
      ..._pois.values.map((p)=>Marker(point:LatLng(p.lat,p.lon),width:40,height:40,child:Tooltip(message:p.label??p.kind,child:const Icon(Icons.location_on,size:38,color:Colors.red)))),
    ];
    return Scaffold(
      appBar:AppBar(title:const Text('SARCADE'),actions:[IconButton(tooltip:'Messages',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MessagesPage(eventId:widget.eventId,actorId:widget.deviceId,sync:_sync,store:widget.store))),icon:Badge(label:Text('${widget.store.pendingCount()}'),child:const Icon(Icons.message))),IconButton(tooltip:'Main courante',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LogbookPage(api:widget.api,eventId:widget.eventId))),icon:const Icon(Icons.receipt_long)),Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Center(child:Text(_status)))]),
      body:FlutterMap(
        mapController:_map,
        options:const MapOptions(initialCenter:LatLng(48.8566,2.3522),initialZoom:11,maxZoom:20),
        children:[
          const MapLibreLayer(initStyle:'https://demotiles.maplibre.org/style.json'),
          MarkerLayer(markers:markers),
          const RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors'),TextSourceAttribution('MapLibre')]),
        ],
      ),
      floatingActionButton:FloatingActionButton.extended(onPressed:_toggleTracking,icon:Icon(_tracking?Icons.location_off:Icons.my_location),label:Text(_tracking?'Arrêter GPS':'Partager position')),
    );
  }
}
