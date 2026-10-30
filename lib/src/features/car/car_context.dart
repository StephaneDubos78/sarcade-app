/// Voice messaging in the car, lot 1a (card « CarPlay et Android Auto »,
/// note « CarPlay et Android Auto », choices of 30 Oct 2026, 18 h 09).
/// Pure code, testable without Flutter.
///
/// - an answer given from a notification, application closed, leaves at
///   once (the car reads, the driver answers: it cannot wait for the
///   application to come back to the foreground);
/// - after a wake-up, the application fetches the message itself from its
///   server, so that the car reads the real text; the text never passes
///   through Google or Apple;
/// - what a background isolate needs (server, event, terminal) is kept in
///   a small file, never in Hive: the application may run at the same time
///   in another isolate.
library;

import '../../models/message.dart';
import '../../offline/sync_operation.dart';
import '../../services/notification_actions.dart';
import '../../services/notification_keys.dart';

/// Server, event and terminal of the application, for a background isolate.
class CarContext {
  final String serverUrl, eventId, deviceId;
  const CarContext({required this.serverUrl,required this.eventId,required this.deviceId});

  bool get isComplete=>serverUrl.trim().isNotEmpty&&eventId.trim().isNotEmpty&&deviceId.trim().isNotEmpty;

  Map<String,dynamic> toJson()=>{'server_url':serverUrl,'event_id':eventId,'device_id':deviceId};

  /// Null when [j] is not a complete context (missing or damaged file).
  static CarContext? fromJson(Object? j){
    if(j is! Map)return null;
    final s=j['server_url'], e=j['event_id'], d=j['device_id'];
    if(s is! String||e is! String||d is! String)return null;
    final c=CarContext(serverUrl:s,eventId:e,deviceId:d);
    return c.isComplete?c:null;
  }

  /// Server address without the final « / ».
  String get base=>serverUrl.trim().replaceFirst(RegExp(r'/+$'),'');
}

/// Synchronisation operation of an answer given from a notification: the
/// same acknowledgement as the one the application queues later from the
/// answers file. The server keeps one acknowledgement per identifier, so
/// the answer sent twice (now, then by the application) stays one.
SyncOperation answerOperation(PendingAnswer a,{required String operationId})=>SyncOperation(
  operationId:operationId,eventId:a.eventId,objectId:a.id,objectType:'ack',action:'create',
  clientTime:a.time,payload:a.toAck());

/// True when the server took the operation (or already had it).
bool operationDelivered(Object? result)=>result is Map&&const {'accepted','duplicate','conflict'}.contains(result['status']);

/// The message announced by a wake-up ([data] of Firebase: event, tag),
/// among the last messages of the event: the one whose notification key is
/// the tag, sent by another terminal. The latest one wins (a distress and
/// its end share the key of the sender).
SarcadeMessage? wokenMessage(Map<String,dynamic> data,Iterable<SarcadeMessage> messages,{required String deviceId}){
  final tag='${data['tag']??''}', eventId='${data['event_id']??''}';
  if(tag.isEmpty)return null;
  SarcadeMessage? found;
  for(final m in messages){
    if(m.deleted||m.senderId==deviceId||(eventId.isNotEmpty&&m.eventId!=eventId))continue;
    if(messageNotificationKey(m)!=tag)continue;
    if(found==null||m.createdAt.isAfter(found.createdAt))found=m;
  }
  return found;
}
