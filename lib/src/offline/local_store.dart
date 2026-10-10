import 'dart:typed_data';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../platform/platform_services.dart';

class LocalStore {
  static const _positions='positions', _pois='pois', _messages='messages', _acks='acks', _references='references', _outbox='outbox', _meta='meta', _features='map_features', _uploads='uploads', _attachments='attachments';
  late Box _positionBox, _poiBox, _messageBox, _ackBox, _referenceBox, _outboxBox, _metaBox, _featureBox, _uploadBox;
  // Photo bytes are read on demand, never all kept in memory.
  late LazyBox _attachmentBox;

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
    _attachmentBox=await Hive.openLazyBox(_attachments);
  }

  Future<void> cachePosition(Map<String,dynamic> v)=>_positionBox.put(v['id'],v);
  Future<void> cachePoi(Map<String,dynamic> v)=>_poiBox.put(v['id'],v);
  Future<void> cacheMessage(Map<String,dynamic> v)=>_messageBox.put(v['id'],v);
  Future<void> cacheAck(Map<String,dynamic> v)=>_ackBox.put(v['id'],v);
  Future<void> cacheReference(Map<String,dynamic> v)=>_referenceBox.put(v['id'],v);
  Future<void> replaceReferences(List<Map<String,dynamic>> values) async {await _referenceBox.clear();for(final v in values){await _referenceBox.put(v['id'],v);}}
  List<Map<String,dynamic>> positions()=>_positionBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> pois()=>_poiBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> messages()=>_messageBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> acks()=>_ackBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> references()=>_referenceBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();

  Future<void> enqueue(Map<String,dynamic> op)=>_outboxBox.put(op['operation_id'],op);
  List<Map<String,dynamic>> pending()=>_outboxBox.values.map((e)=>Map<String,dynamic>.from(e)).toList()
    ..sort((a,b)=>(a['client_time'] as String).compareTo(b['client_time'] as String));
  Future<void> acknowledge(String operationId)=>_outboxBox.delete(operationId);
  int pendingCount()=>_outboxBox.length;

  // Drawn map objects, kept locally until the server exposes a map object API.
  List<Map<String,dynamic>> mapFeatures(String eventId)=>_featureBox.values.map((e)=>Map<String,dynamic>.from(e as Map)).where((j)=>j['event_id']==eventId).toList();
  Future<void> saveMapFeature(Map<String,dynamic> v)=>_featureBox.put(v['id'],v);
  Future<void> deleteMapFeature(String id)=>_featureBox.delete(id);

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

  String cursor(String eventId)=>_metaBox.get('cursor:$eventId',defaultValue:'0') as String;
  Future<void> setCursor(String eventId,String cursor)=>_metaBox.put('cursor:$eventId',cursor);
}
