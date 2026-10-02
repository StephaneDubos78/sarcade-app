import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../services/sarcade_api.dart';
import 'local_store.dart';
import 'sync_operation.dart';

class OfflineSyncService {
  final SarcadeApi api; final LocalStore store; final String eventId;
  final _uuid=const Uuid(); StreamSubscription? _network; bool _syncing=false;
  OfflineSyncService({required this.api,required this.store,required this.eventId});

  void start(){
    _network=Connectivity().onConnectivityChanged.listen((_){syncNow();});
    syncNow();
  }

  Future<void> queue({required String objectId,required String objectType,required Map<String,dynamic> payload}) async {
    final op=SyncOperation(operationId:_uuid.v4(),eventId:eventId,objectId:objectId,objectType:objectType,action:'create',clientTime:DateTime.now().toUtc(),payload:payload);
    await store.enqueue(op.toJson());
    await syncNow();
  }

  Future<void> syncNow() async {
    if(_syncing)return; _syncing=true;
    try {
      final pending=store.pending();
      if(pending.isNotEmpty){
        final results=await api.sync(pending);
        for(final r in results){
          if(r['status']=='accepted'||r['status']=='duplicate') await store.acknowledge(r['operation_id']);
        }
      }
      final cursor=int.tryParse(store.cursor(eventId))??0;
      final feed=await api.changes(eventId,cursor);
      for(final c in feed.changes){
        final p=Map<String,dynamic>.from(c['payload']);
        if(c['object_type']=='position') await store.cachePosition(p);
        if(c['object_type']=='poi') await store.cachePoi(p);
      }
      await store.setCursor(eventId,feed.nextCursor);
    } catch(_){
      // Offline is an expected state. The outbox remains persistent for retry.
    } finally {_syncing=false;}
  }

  Future<void> dispose() async => _network?.cancel();
}
