import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../operations/event_settings.dart';
import '../services/sarcade_api.dart';
import 'local_store.dart';
import 'outbox_policy.dart';
import 'sync_operation.dart';

/// Object types of routes and navigation, cached in one box.
const routeObjectKinds={'route','route_waypoint','route_passage','road_closure','itinerary','move_order'};

class OfflineSyncService {
  final SarcadeApi api; final LocalStore store; final String eventId;
  /// Called for every change of the feed, after it is cached locally.
  final void Function(String objectType,Map<String,dynamic> payload)? onRemoteChange;
  final _uuid=const Uuid(); StreamSubscription? _network; Timer? _periodic; bool _syncing=false, _again=false;
  Timer? _batch; bool _lowBandwidth=false; int _batchSeconds=60;
  /// Automatic synchronisation even without user action: pulls changes that
  /// the real-time channel may have missed and retries pending sends and
  /// photo uploads (test of 14 Oct 2026: photos only came after the button).
  /// Paused in low-bandwidth mode, where the PCO interval applies instead.
  static const autoInterval=Duration(seconds:20);
  /// Result of the last exchange with the server, for the status shown at
  /// the top of the screen. « Hors connexion » means the server did not
  /// answer at all: a refusal or a server error is an answer, the server is
  /// reachable (« Robustesse de la synchronisation »).
  bool lastSyncOk=false; DateTime? lastServerContact;
  /// The current event does not exist on this server (changes feed 404).
  bool eventUnknown=false;
  OfflineSyncService({required this.api,required this.store,required this.eventId,this.onRemoteChange});

  String get server=>api.baseUrl;
  List<Map<String,dynamic>> get _all=>store.pending();
  /// Items of this server and event on their way.
  int get inFlight=>inFlightCount(_all,server,eventId,DateTime.now().toUtc());
  /// Items still on the device that are « non envoyés » (set aside, failing
  /// for too long, or waiting for another server or event).
  int get unsent=>unsentCount(_all,server,eventId,DateTime.now().toUtc());
  /// Items of this server and event, for the delay alert.
  List<Map<String,dynamic>> get currentItems=>_all.where((op)=>belongsTo(op,server,eventId)).toList();

  /// The service of the open map, so that « Envoyer d'abord » in the
  /// settings uses it instead of a second sender on the same Outbox.
  static OfflineSyncService? active;

  void start(){
    active=this;
    _network=Connectivity().onConnectivityChanged.listen((_){syncNow();});
    _periodic=Timer.periodic(autoInterval,(_){if(!_lowBandwidth)syncNow();});
    syncNow();
  }

  /// Low-bandwidth mode imposed by the PCO: grouped sending every
  /// [intervalS] seconds, photos kept on the device until the mode is lifted,
  /// urgent and immediate messages still sent at once.
  bool get lowBandwidth=>_lowBandwidth;
  void setLowBandwidth(bool on,{int intervalS=60}){
    if(on==_lowBandwidth&&intervalS==_batchSeconds)return;
    final lifted=_lowBandwidth&&!on;
    _lowBandwidth=on; _batchSeconds=intervalS;
    _batch?.cancel(); _batch=null;
    if(on){_batch=Timer.periodic(Duration(seconds:intervalS),(_){syncNow();});}
    // Lifting the mode sends at once what waited, photos included.
    if(lifted)syncNow();
  }

  Future<void> queue({required String objectId,required String objectType,required Map<String,dynamic> payload,String action='create'}) async {
    final op=SyncOperation(operationId:_uuid.v4(),eventId:eventId,objectId:objectId,objectType:objectType,action:action,clientTime:DateTime.now().toUtc(),payload:payload);
    // Each item remembers the server and event it was created for.
    final json=op.toJson()..[localKey]=newLocal(server);
    await store.enqueue(json);
    // In low-bandwidth mode only urgent and immediate messages leave at once.
    if(!_lowBandwidth||isUrgentOperation(json))await syncNow();
  }

  /// True while a local change of this object waits in the Outbox.
  bool isPending(String objectId)=>currentItems.any((op)=>op['object_id']==objectId&&!isSetAside(op));

  Future<void> syncNow() async {
    // A change queued during a sync is sent right after it, not dropped.
    if(_syncing){_again=true;return;}
    _syncing=true;
    try {
      // Photos first: a message is only sent once its photos are on the server.
      // In low-bandwidth mode photos stay on the device and messages leave
      // without waiting for them (the photos follow when the mode is lifted).
      if(!_lowBandwidth)await _uploadPending();
      final waiting=_lowBandwidth?<String>{}:store.pendingUploads().map((u)=>u['file_id'] as String).toSet();
      // Several rounds so that a long queue empties at once, batch by batch.
      // An item is tried once per synchronisation, so that 3 tries mean 3
      // synchronisations, not 3 rounds of the same one.
      final tried=<String>{};
      for(var round=0;round<20;round++){
        final batch=nextBatch(_all.where((op)=>!tried.contains(op['operation_id'])).toList(),server,eventId,waiting);
        if(batch.isEmpty)break;
        tried.addAll(batch.map((op)=>'${op['operation_id']}'));
        final progressed=await _send(batch);
        if(!progressed)break;
      }
      final cursor=int.tryParse(store.cursor(eventId))??0;
      final feed=await _changes(cursor);
      if(feed==null)return;
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
        if(routeObjectKinds.contains(c['object_type'])&&!isPending(c['object_id'] as String)){
          if(p['deleted']==true){await store.deleteRouteObject(c['object_id'] as String);}
          else{await store.saveRouteObject({...p,'kind':c['object_type']});}
        }
        if(c['object_type']=='comm_group'&&!isPending(c['object_id'] as String)){
          if(p['deleted']==true){await store.deleteGroup(c['object_id'] as String);}
          else{await store.saveGroup(p);}
        }
        onRemoteChange?.call(c['object_type'] as String,p);
      }
      await store.setCursor(eventId,feed.nextCursor);
      lastSyncOk=true; lastServerContact=DateTime.now();
    } on SarcadeHttpException {
      // Any HTTP answer means the server is reachable.
      lastSyncOk=true; lastServerContact=DateTime.now();
    } catch(_){
      lastSyncOk=false;
      // Offline is an expected state. The outbox remains persistent for retry.
    } finally {
      _syncing=false;
      if(_again){_again=false;unawaited(syncNow());}
    }
  }

  /// Changes feed of the event, or null when the server refuses it (the
  /// server answered: it is reachable; a 404 means the event is not there).
  Future<({List<Map<String,dynamic>> changes,String nextCursor})?> _changes(int cursor) async {
    try{
      final feed=await api.changes(eventId,cursor);
      eventUnknown=false;
      return feed;
    }on SarcadeHttpException catch(e){
      eventUnknown=e.statusCode==404;
      lastSyncOk=true; lastServerContact=DateTime.now();
      return null;
    }
  }

  /// Sends a batch and applies the answer item by item. If the whole batch
  /// fails (server error, older server), the items are sent one by one to
  /// isolate the faulty one. Returns false when nothing could be settled, to
  /// stop the round. Network errors are rethrown: the server is unreachable.
  Future<bool> _send(List<Map<String,dynamic>> batch) async {
    try{
      final results=await api.sync(batch.map(wire).toList());
      lastSyncOk=true; lastServerContact=DateTime.now();
      return await _apply(batch,results);
    }on SarcadeHttpException catch(e){
      lastSyncOk=true; lastServerContact=DateTime.now();
      if(batch.length==1){
        await _fail(batch.single,status:'retry',reason:'erreur du serveur (${e.statusCode})');
        return false;
      }
      var progressed=false;
      for(final op in batch){
        try{
          final r=await api.sync([wire(op)]);
          progressed=await _apply([op],r)||progressed;
        }on SarcadeHttpException catch(e1){
          await _fail(op,status:'retry',reason:'erreur du serveur (${e1.statusCode})');
        }
      }
      return progressed;
    }
  }

  Future<bool> _apply(List<Map<String,dynamic>> batch,List<Map<String,dynamic>> results) async {
    final byId={for(final r in results)'${r['operation_id']}':r};
    var progressed=false;
    for(final op in batch){
      final r=byId['${op['operation_id']}'];
      final status=r?['status'] as String?;
      switch(outcomeOf(status)){
        case SyncOutcome.remove: await store.acknowledge(op['operation_id'] as String); progressed=true;
        case SyncOutcome.setAside: await _fail(op,status:status,reason:r?['reason'] as String?,setAside:true); progressed=true;
        case SyncOutcome.retry: await _fail(op,status:status??'retry',reason:r?['reason'] as String?);
      }
    }
    return progressed;
  }

  Future<void> _fail(Map<String,dynamic> op,{String? status,String? reason,bool setAside=false})=>
    store.updatePending(afterFailure(op,DateTime.now().toUtc(),status:status,reason:reason??_defaultReason(status),setAside:setAside));

  static String? _defaultReason(String? status)=>switch(status){
    'unknown_event'=>'événement inconnu de ce serveur',
    'rejected'=>'refusé par le serveur',
    _=>null,
  };

  /// « Réessayer » from the « Éléments non envoyés » screen.
  Future<void> retry(Map<String,dynamic> op) async {await store.updatePending(resetForRetry(op));await syncNow();}

  /// « Rattacher à l'événement en cours » (messages, map objects, POI).
  Future<void> attachHere(Map<String,dynamic> op) async {await store.updatePending(attachedTo(op,server,eventId));await syncNow();}

  /// « Supprimer », after confirmation: traced in the local journal.
  Future<void> discard(Map<String,dynamic> op,String actorId) async {
    await store.addLocalJournal({'time':DateTime.now().toUtc().toIso8601String(),'action':'unsent_deleted',
      'actor_id':actorId,'operation_id':op['operation_id'],'object_type':op['object_type'],'object_id':op['object_id'],
      'event_id':op['event_id'],'server':itemServer(op),'reason':reasonOf(op),'summary':itemSummary(op)});
    await store.acknowledge(op['operation_id'] as String);
  }

  Future<void> _uploadPending() async {
    for(final u in store.pendingUploads()){
      final id=u['file_id'] as String;
      // Photos of another event wait until the operator goes back to it.
      if((u['event_id'] as String?)!=null&&u['event_id']!=eventId)continue;
      final bytes=await store.attachment(id);
      if(bytes==null){await store.uploadDone(id);continue;}
      try{
        await api.uploadFile((u['event_id'] as String?)??eventId,u['sender_id'] as String,u['name'] as String,u['mime_type'] as String,bytes,fileId:id);
        await store.uploadDone(id);
      }on SarcadeHttpException catch(e){
        // A refused photo (too large, unknown event) must not block the
        // message forever: it is sent without the photo being available.
        // An unknown event keeps the photo on the device, never thrown away.
        if(e.statusCode==404&&e.body.contains('unknown_event'))continue;
        if(e.isPermanent){await store.uploadDone(id);}else{return;}
      }
    }
  }

  Future<void> dispose() async {if(identical(active,this))active=null;_periodic?.cancel();_batch?.cancel();await _network?.cancel();}
}
