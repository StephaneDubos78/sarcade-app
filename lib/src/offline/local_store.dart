import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class LocalStore {
  static const _positions='positions', _pois='pois', _outbox='outbox', _meta='meta';
  late Box _positionBox, _poiBox, _outboxBox, _metaBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _positionBox=await Hive.openBox(_positions);
    _poiBox=await Hive.openBox(_pois);
    _outboxBox=await Hive.openBox(_outbox);
    _metaBox=await Hive.openBox(_meta);
  }

  Future<void> cachePosition(Map<String,dynamic> value)=>_positionBox.put(value['id'],value);
  Future<void> cachePoi(Map<String,dynamic> value)=>_poiBox.put(value['id'],value);
  List<Map<String,dynamic>> positions()=>_positionBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> pois()=>_poiBox.values.map((e)=>Map<String,dynamic>.from(e)).toList();

  Future<void> enqueue(Map<String,dynamic> op)=>_outboxBox.put(op['operation_id'],op);
  List<Map<String,dynamic>> pending()=>_outboxBox.values.map((e)=>Map<String,dynamic>.from(e)).toList()
    ..sort((a,b)=>(a['client_time'] as String).compareTo(b['client_time'] as String));
  Future<void> acknowledge(String operationId)=>_outboxBox.delete(operationId);

  String cursor(String eventId)=>_metaBox.get('cursor:$eventId',defaultValue:'0') as String;
  Future<void> setCursor(String eventId,String cursor)=>_metaBox.put('cursor:$eventId',cursor);
}
