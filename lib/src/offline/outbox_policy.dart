/// Outbox rules of « Robustesse de la synchronisation » (decisions of
/// 23 October 2026): pure helpers, testable without Flutter.
///
/// - an item refused by the server never blocks the others;
/// - no data is lost silently: an item that cannot leave stays visible,
///   with its reason;
/// - each item belongs to the server and the event it was created for, and
///   is only sent there;
/// - urgent and immediate messages always leave first.
library;

import '../features/messages/photo_attachment.dart';
import '../operations/event_settings.dart';

/// Local bookkeeping kept with each Outbox item, never sent to the server.
const localKey='_local';

/// A transient failure turns an item into « non envoyé » after 3 tries or
/// 5 minutes (decision 2). It is still retried automatically.
const maxAttempts=3;
const unsentAfter=Duration(minutes:5);

/// Batches stay small so that a large one does not hold the link.
const maxBatch=50;

/// What the client does with an item after the server answered.
enum SyncOutcome{remove,setAside,retry}

SyncOutcome outcomeOf(String? status)=>switch(status){
  'accepted'||'duplicate'||'conflict'=>SyncOutcome.remove,
  // rejected can never apply; unknown_event is kept, never thrown away.
  'rejected'||'unknown_event'=>SyncOutcome.setAside,
  _=>SyncOutcome.retry,
};

Map<String,dynamic> _local(Map<String,dynamic> op){
  final v=op[localKey];
  return v is Map?Map<String,dynamic>.from(v):<String,dynamic>{};
}

/// Normalised server address, so that « http://nas:8000/ » and
/// « http://nas:8000 » are the same server.
String normalServer(String url){
  var s=url.trim();
  while(s.endsWith('/')){s=s.substring(0,s.length-1);}
  return s.toLowerCase();
}

/// Local fields of a new item.
Map<String,dynamic> newLocal(String server)=>{'server':normalServer(server),'attempts':0,'state':'pending'};

String? itemServer(Map<String,dynamic> op)=>_local(op)['server'] as String?;
String itemEvent(Map<String,dynamic> op)=>'${op['event_id']}';
int attempts(Map<String,dynamic> op)=>(_local(op)['attempts'] as num?)?.toInt()??0;
String? reasonOf(Map<String,dynamic> op)=>_local(op)['reason'] as String?;
String? lastStatus(Map<String,dynamic> op)=>_local(op)['status'] as String?;
bool isSetAside(Map<String,dynamic> op)=>_local(op)['state']=='set_aside';
DateTime? firstFailure(Map<String,dynamic> op)=>DateTime.tryParse('${_local(op)['first_failure_at']}');

/// Items queued before this version have no server: they are taken as
/// belonging to the current server and are sorted out by its answer.
bool belongsTo(Map<String,dynamic> op,String server,String eventId){
  final s=itemServer(op);
  return itemEvent(op)==eventId&&(s==null||s==normalServer(server));
}

/// « Non envoyé »: set aside by the server, or still failing after 3 tries
/// or 5 minutes, or waiting for another server or event.
bool isUnsent(Map<String,dynamic> op,String server,String eventId,DateTime now){
  if(!belongsTo(op,server,eventId)||isSetAside(op))return true;
  final first=firstFailure(op);
  return attempts(op)>=maxAttempts||(first!=null&&now.difference(first)>=unsentAfter);
}

/// Priorities of « Synchronisation client-serveur »: urgent and immediate
/// messages, ACK, positions, everything else. Photos travel separately.
int priorityClass(Map<String,dynamic> op){
  if(isUrgentOperation(op))return 0;
  return switch(op['object_type']){'ack'=>1,'position'=>2,_=>3};
}

/// The next batch for this server and event: items set aside or waiting
/// for a photo stay out, the rest is ordered by priority then by time. Two
/// changes of the same object share a class and keep their order.
List<Map<String,dynamic>> nextBatch(List<Map<String,dynamic>> all,String server,String eventId,Set<String> waitingFileIds){
  final mine=all.where((op)=>belongsTo(op,server,eventId)&&!isSetAside(op)).toList();
  final ready=readyOperations(mine,waitingFileIds);
  final indexed=[for(var i=0;i<ready.length;i++)(i,ready[i])];
  indexed.sort((a,b){
    final c=priorityClass(a.$2).compareTo(priorityClass(b.$2));
    if(c!=0)return c;
    final t='${a.$2['client_time']}'.compareTo('${b.$2['client_time']}');
    return t!=0?t:a.$1.compareTo(b.$1);
  });
  return indexed.take(maxBatch).map((e)=>e.$2).toList();
}

/// The item as the server expects it, without the local fields.
Map<String,dynamic> wire(Map<String,dynamic> op)=>Map<String,dynamic>.from(op)..remove(localKey);

/// Item after a failed attempt ([setAside] for rejected or unknown event).
Map<String,dynamic> afterFailure(Map<String,dynamic> op,DateTime now,{String? status,String? reason,bool setAside=false}){
  final l=_local(op);
  l['attempts']=attempts(op)+1;
  l['first_failure_at']??=now.toUtc().toIso8601String();
  if(status!=null)l['status']=status;
  if(reason!=null)l['reason']=reason;
  if(setAside)l['state']='set_aside';
  return Map<String,dynamic>.from(op)..[localKey]=l;
}

/// « Réessayer »: the item goes back to the queue with its counters reset.
Map<String,dynamic> resetForRetry(Map<String,dynamic> op){
  final l=_local(op)..remove('first_failure_at')..remove('status')..remove('reason');
  l['attempts']=0; l['state']='pending';
  return Map<String,dynamic>.from(op)..[localKey]=l;
}

/// Messages, map objects and POI can move to the current event; positions
/// never (decision 4), nor acknowledgements of another event's messages.
bool canAttach(Map<String,dynamic> op)=>const {'message','map_feature','poi'}.contains(op['object_type']);

/// « Rattacher à l'événement en cours ».
Map<String,dynamic> attachedTo(Map<String,dynamic> op,String server,String eventId){
  if(!canAttach(op))throw ArgumentError('cannot attach ${op['object_type']}');
  final payload=op['payload'] is Map?Map<String,dynamic>.from(op['payload'] as Map):<String,dynamic>{};
  if(payload.containsKey('event_id'))payload['event_id']=eventId;
  final out=resetForRetry(Map<String,dynamic>.from(op)..['event_id']=eventId..['payload']=payload);
  final l=Map<String,dynamic>.from(out[localKey] as Map)..['server']=normalServer(server);
  return out..[localKey]=l;
}

/// Number of items still on the device that are « non envoyés ».
int unsentCount(List<Map<String,dynamic>> all,String server,String eventId,DateTime now)=>
  all.where((op)=>isUnsent(op,server,eventId,now)).length;

/// Items of this server and event that are on their way (not unsent).
int inFlightCount(List<Map<String,dynamic>> all,String server,String eventId,DateTime now)=>
  all.where((op)=>belongsTo(op,server,eventId)&&!isUnsent(op,server,eventId,now)).length;

/// Items waiting for [server] and [eventId], whatever their state: the
/// warning before changing server or event (decision 5).
int waitingFor(List<Map<String,dynamic>> all,String server,String eventId)=>
  all.where((op)=>belongsTo(op,server,eventId)).length;

/// One line of text describing the item, for the « Éléments non envoyés » list.
String itemSummary(Map<String,dynamic> op){
  final p=op['payload'] is Map?op['payload'] as Map:const {};
  String cut(Object? v){final s='${v??''}'.trim();return s.length>60?'${s.substring(0,57)}…':s;}
  return switch(op['object_type']){
    'message'=>cut(p['body']),
    'map_feature'=>cut(p['label']).isEmpty?'${p['kind']??''}':cut(p['label']),
    'poi'=>cut(p['label']??p['kind']),
    'ack'=>'${p['status']??''}',
    'position'=>(p['lat'] is num&&p['lon'] is num)?'${(p['lat'] as num).toStringAsFixed(5)}, ${(p['lon'] as num).toStringAsFixed(5)}':'',
    _=>'',
  };
}
