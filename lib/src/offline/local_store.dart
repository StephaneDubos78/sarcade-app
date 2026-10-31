import 'dart:typed_data';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../platform/platform_services.dart';
import '../features/messages/message_deletion.dart';

class LocalStore {
  static const _positions='positions', _pois='pois', _messages='messages', _acks='acks', _references='references', _outbox='outbox', _meta='meta', _features='map_features', _uploads='uploads', _attachments='attachments', _groups='comm_groups', _routeObjects='route_objects';
  late Box _positionBox, _poiBox, _messageBox, _ackBox, _referenceBox, _outboxBox, _metaBox, _featureBox, _uploadBox, _groupBox, _routeBox;
  // Photo bytes are read on demand, never all kept in memory.
  late LazyBox _attachmentBox;
  // Road graph of navigation on the device (tens of MB), read on demand.
  late LazyBox _graphBox;

  Future<void> init() async {
    await initHiveStorage();
    _positionBox=await Hive.openBox(_positions);
    _poiBox=await Hive.openBox(_pois);
    _messageBox=await Hive.openBox(_messages);
    _ackBox=await Hive.openBox(_acks);
    _referenceBox=await Hive.openBox(_references);
    _outboxBox=await Hive.openBox(_outbox);
    _metaBox=await Hive.openBox(_meta);
    _featureBox=await Hive.openBox(_features);
    _uploadBox=await Hive.openBox(_uploads);
    _groupBox=await Hive.openBox(_groups);
    _routeBox=await Hive.openBox(_routeObjects);
    _attachmentBox=await Hive.openLazyBox(_attachments);
    _graphBox=await Hive.openLazyBox('road_graph');
  }

  Future<void> cachePosition(Map<String,dynamic> v)=>_positionBox.put(v['id'],v);
  Future<void> cachePoi(Map<String,dynamic> v)=>_poiBox.put(v['id'],v);
  Future<void> deletePoi(String id)=>_poiBox.delete(id);
  /// A deletion is merged onto the known message, which never comes back
  /// with its text (see message_deletion.dart).
  Future<void> cacheMessage(Map<String,dynamic> v) async {
    final old=_messageBox.get(v['id']);
    final merged=mergeCachedMessage(old is Map?Map<String,dynamic>.from(old):null,v);
    if(merged!=null)await _messageBox.put(v['id'],merged);
  }
  Future<void> cacheAck(Map<String,dynamic> v)=>_ackBox.put(v['id'],v);
  Future<void> cacheReference(Map<String,dynamic> v)=>_referenceBox.put(v['id'],v);
  Future<void> replaceReferences(List<Map<String,dynamic>> values) async {await _referenceBox.clear();for(final v in values){await _referenceBox.put(v['id'],v);}}
  List<Map<String,dynamic>> positions()=>_positionBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> pois()=>_poiBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> messages()=>_messageBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  /// Changes of messages and acknowledgements, from any source (real time,
  /// synchronisation, this device), so open screens can refresh.
  /// Messages, receipts and channels (a channel archived on another device
  /// disappears at once, card « Ordre des pastilles de groupes »).
  List<Stream<BoxEvent>> messageChanges()=>[_messageBox.watch(),_ackBox.watch(),_groupBox.watch()];
  List<Map<String,dynamic>> acks()=>_ackBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> references()=>_referenceBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();

  Future<void> enqueue(Map<String,dynamic> op)=>_outboxBox.put(op['operation_id'],op);
  List<Map<String,dynamic>> pending()=>_outboxBox.values.map((e)=>Map<String,dynamic>.from(e)).toList()
    ..sort((a,b)=>(a['client_time'] as String).compareTo(b['client_time'] as String));
  Future<void> acknowledge(String operationId)=>_outboxBox.delete(operationId);
  /// Replaces an Outbox item (state after an attempt, retry, new event).
  Future<void> updatePending(Map<String,dynamic> op)=>_outboxBox.put(op['operation_id'],op);
  int pendingCount()=>_outboxBox.length;

  /// Local journal of the device: deletions of unsent items by the operator
  /// (decision 3 of « Robustesse de la synchronisation »).
  List<Map<String,dynamic>> localJournal(){final v=_metaBox.get('local_journal');return v is List?v.map((e)=>Map<String,dynamic>.from(e as Map)).toList():[];}
  Future<void> addLocalJournal(Map<String,dynamic> entry) async {
    final all=localJournal()..add(entry);
    await _metaBox.put('local_journal',all.length>500?all.sublist(all.length-500):all);
  }

  /// Last list of events received from a server, shown without network
  /// (« Choix de l'événement dans une liste »).
  List<Map<String,dynamic>> cachedEvents(String server){final v=_metaBox.get('events:${server.toLowerCase()}');return v is List?v.map((e)=>Map<String,dynamic>.from(e as Map)).toList():[];}
  Future<void> saveEvents(String server,List<Map<String,dynamic>> events)=>_metaBox.put('events:${server.toLowerCase()}',events);

  // Drawn map objects, kept locally until the server exposes a map object API.
  List<Map<String,dynamic>> mapFeatures(String eventId)=>_featureBox.values.map((e)=>Map<String,dynamic>.from(e as Map)).where((j)=>j['event_id']==eventId).toList();
  Future<void> saveMapFeature(Map<String,dynamic> v)=>_featureBox.put(v['id'],v);
  Future<void> deleteMapFeature(String id)=>_featureBox.delete(id);

  // Communication groups of the events, from the change feed and the list.
  List<Map<String,dynamic>> groups(String eventId)=>_groupBox.values.map((e)=>Map<String,dynamic>.from(e as Map)).where((j)=>j['event_id']==eventId).toList();
  Future<void> saveGroup(Map<String,dynamic> v)=>_groupBox.put(v['id'],v);
  Future<void> deleteGroup(String id)=>_groupBox.delete(id);

  // Routes, waypoints, passages, road closures and itineraries of the events.
  List<Map<String,dynamic>> routeObjects(String eventId)=>_routeBox.values.map((e)=>Map<String,dynamic>.from(e as Map)).where((j)=>j['event_id']==eventId).toList();
  Future<void> saveRouteObject(Map<String,dynamic> v)=>_routeBox.put(v['id'],v);
  Future<void> deleteRouteObject(String id)=>_routeBox.delete(id);

  // Photos of messages: bytes cached by file id, and the uploads still to do.
  Future<void> saveAttachment(String fileId,Uint8List bytes)=>_attachmentBox.put(fileId,bytes);
  Future<Uint8List?> attachment(String fileId) async {
    final v=await _attachmentBox.get(fileId);
    if(v is Uint8List)return v;
    if(v is List)return Uint8List.fromList(v.cast<int>());
    return null;
  }
  Future<void> queueUpload(Map<String,dynamic> meta)=>_uploadBox.put(meta['file_id'],meta);
  List<Map<String,dynamic>> pendingUploads()=>_uploadBox.values.map((e)=>Map<String,dynamic>.from(e as Map)).toList()
    ..sort((a,b)=>(a['created_at'] as String).compareTo(b['created_at'] as String));
  bool isUploadPending(String fileId)=>_uploadBox.containsKey(fileId);
  Future<void> uploadDone(String fileId)=>_uploadBox.delete(fileId);

  Map<String,dynamic>? storedConfig(){final v=_metaBox.get('config');return v==null?null:Map<String,dynamic>.from(v as Map);}
  Future<void> saveConfig(Map<String,dynamic> v)=>_metaBox.put('config',v);

  // Last event settings received from the server, kept for offline starts.
  Map<String,dynamic>? eventSettings(String eventId){final v=_metaBox.get('settings:$eventId');return v==null?null:Map<String,dynamic>.from(v as Map);}
  Future<void> saveEventSettings(String eventId,Map<String,dynamic> v)=>_metaBox.put('settings:$eventId',v);

  // Position tracking (Beacon) chosen by the operator for an event.
  ({bool enabled,int intervalS})? trackingPrefs(String eventId){
    final v=_metaBox.get('tracking:$eventId');
    if(v is! Map)return null;
    return (enabled:v['enabled']==true,intervalS:(v['interval_s'] as num?)?.toInt()??30);
  }
  Future<void> saveTrackingPrefs(String eventId,bool enabled,int intervalS)=>_metaBox.put('tracking:$eventId',{'enabled':enabled,'interval_s':intervalS});

  Future<void> saveRoadGraph(Uint8List bytes,Map<String,dynamic> info) async {await _graphBox.put('graph',bytes);await _metaBox.put('road_graph_info',info);}
  Future<Uint8List?> roadGraph() async {
    final v=await _graphBox.get('graph');
    if(v is Uint8List)return v;
    if(v is List)return Uint8List.fromList(v.cast<int>());
    return null;
  }
  Map<String,dynamic>? roadGraphInfo(){final v=_metaBox.get('road_graph_info');return v==null?null:Map<String,dynamic>.from(v as Map);}

  // Small server answers kept for offline use (weather, base map catalog).
  Map<String,dynamic>? cachedJson(String key){final v=_metaBox.get('cache:$key');return v==null?null:Map<String,dynamic>.from(v as Map);}
  Future<void> cacheJson(String key,Map<String,dynamic> v)=>_metaBox.put('cache:$key',v);
  String? preference(String key)=>_metaBox.get('pref:$key') as String?;
  Future<void> setPreference(String key,String? v)=>v==null?_metaBox.delete('pref:$key'):_metaBox.put('pref:$key',v);

  /// Messages already shown on the messages screen (null: never opened on
  /// this device for this event).
  Set<String>? seenMessages(String eventId){final v=_metaBox.get('seen:$eventId');return v is List?v.map((e)=>'$e').toSet():null;}
  Future<void> markMessagesSeen(String eventId,Iterable<String> ids) async {
    final all={...?seenMessages(eventId),...ids};
    await _metaBox.put('seen:$eventId',all.toList());
  }
  String cursor(String eventId)=>_metaBox.get('cursor:$eventId',defaultValue:'0') as String;
  Future<void> setCursor(String eventId,String cursor)=>_metaBox.put('cursor:$eventId',cursor);
}
