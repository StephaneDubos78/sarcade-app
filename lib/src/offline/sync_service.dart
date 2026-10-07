import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../services/sarcade_api.dart';
import 'local_store.dart';
import 'sync_operation.dart';

/// Server statuses after which an operation must leave the Outbox.
/// `conflict` lost against a newer change and `rejected` can never apply:
/// retrying them would loop forever. The winning state comes from the feed.
const _finalStatuses={'accepted','duplicate','conflict','rejected'};

class OfflineSyncService {
  final SarcadeApi api; final LocalStore store; final String eventId;
  /// Called for every change of the feed, after it is cached locally.
  final void Function(String objectType,Map<String,dynamic> payload)? onRemoteChange;
  final _uuid=const Uuid(); StreamSubscription? _network; bool _syncing=false, _again=false;
  OfflineSyncService({required this.api,required this.store,required this.eventId,this.onRemoteChange});

  void start(){
    _network=Connectivity().onConnectivityChanged.listen((_){syncNow();});
    syncNow();
  }

  Future<void> queue({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {
    final op=SyncOperation(operationId:_uuid.v4(),eventId:eventId,objectId:objectId,objectType:objectType,action:action,clientTime:DateTime.now().toUtc(),payload:payload);
    await store.enqueue(op.toJson());
    await syncNow();
  }

  /// True while a local change of this object waits in the Outbox.
  bool isPending(String objectId)=>store.pending().any((op)=>op['object_id']==objectId);

  Future<void> syncNow() async {
    // A change queued during a sync is sent right after it, not dropped.
    if(_syncing){_again=true;return;}
    _syncing=true;
    try {
      final pending=store.pending();
      if(pending.isNotEmpty){
        final results=await api.sync(pending);
        for(final r in results){
          if(_finalStatuses.contains(r['status'])) await store.acknowledge(r['operation_id']);
        }
      }
      final cursor=int.tryParse(store.cursor(eventId))??0;
      final feed=await api.changes(eventId,cursor);
      for(final c in feed.changes){
        final p=Map<String,dynamic>.from(c['payload']);
        if(c['object_type']=='position') await store.cachePosition(p);
        if(c['object_type']=='poi') await store.cachePoi(p);
        if(c['object_type']=='message') await store.cacheMessage(p);
        if(c['object_type']=='ack') await store.cacheAck(p);
        // A pending local change wins locally until the server has ruled on it.
        if(c['object_type']=='map_feature'&&!isPending(c['object_id'] as String)){
          if(p['deleted']==true){await store.deleteMapFeature(c['object_id'] as String);}
          else{await store.saveMapFeature(p);}
        }
        onRemoteChange?.call(c['object_type'] as String,p);
      }
      await store.setCursor(eventId,feed.nextCursor);
    } catch(_){
      // Offline is an expected state. The outbox remains persistent for retry.
    } finally {
      _syncing=false;
      if(_again){_again=false;unawaited(syncNow());}
    }
  }

  Future<void> dispose() async => _network?.cancel();
}
