/// Actions of the message notifications (decisions of 10 Oct 2026), shared
/// by every platform. Pure code.
///
/// - urgent and immediate messages: Accept, Refuse, Open;
/// - routine messages: Read, Open;
/// - the answer is an acknowledgement of the message, queued in the Outbox
///   like an answer given in the messages screen, even when the action is
///   tapped with the application closed;
/// - immediate messages: distinct sound and vibration, reminder every
///   2 minutes, at most 3 times, until the operator answers.
library;

import 'dart:convert';

const actionAccept='accept', actionRefuse='refuse', actionRead='read', actionOpen='open';
const reminderInterval=Duration(minutes:2);
const reminderCount=3;

bool isUrgentPriority(String priority)=>priority=='urgent'||priority=='immediate';

/// Buttons shown on the notification of a message, in order.
List<String> actionsFor(String priority)=>isUrgentPriority(priority)
  ?const [actionAccept,actionRefuse,actionOpen]:const [actionRead,actionOpen];

/// Acknowledgement status given by an action; null for Open (or a tap on the
/// notification itself), which only opens the message.
String? ackStatusForAction(String? action)=>switch(action){
  actionAccept=>'accepted',
  actionRefuse=>'rejected',
  actionRead=>'read',
  _=>null,
};

/// An answer stops the reminders of an immediate message.
bool stopsReminders(String status)=>status=='accepted'||status=='rejected'||status=='read';

/// What the notification carries to find the message again, even in a
/// background isolate without the application state.
class NotificationPayload {
  final String eventId, messageId, deviceId, priority;
  const NotificationPayload({required this.eventId,required this.messageId,required this.deviceId,required this.priority});

  String encode([String? action])=>jsonEncode({'e':eventId,'m':messageId,'d':deviceId,'p':priority,'a':?action});

  static NotificationPayload? decode(String? text){
    if(text==null||text.isEmpty)return null;
    try{
      final j=jsonDecode(text);
      if(j is! Map||j['m'] is! String||j['e'] is! String)return null;
      return NotificationPayload(eventId:j['e'] as String,messageId:j['m'] as String,
        deviceId:(j['d'] as String?)??'',priority:(j['p'] as String?)??'routine');
    }catch(_){
      return null;
    }
  }

  /// Action carried in the payload itself (Windows gives back the arguments
  /// of the button as payload).
  static String? actionIn(String? text){
    try{
      final j=jsonDecode(text??'');
      return j is Map?j['a'] as String?:null;
    }catch(_){
      return null;
    }
  }
}

/// Resolves the action of a notification response: the action identifier
/// given by the platform, else the one carried in the payload, else Open.
String resolveAction(String? actionId,String? payload){
  final fromPayload=NotificationPayload.actionIn(payload);
  if(actionId!=null&&actionId.isNotEmpty&&!actionId.startsWith('{'))return actionId;
  return fromPayload??actionOpen;
}

/// Stable notification identifiers of a message: the notification itself,
/// then its reminders (1 to [reminderCount]). Below 2^31 on every platform.
int notificationIdFor(String messageId,[int reminder=0]){
  var h=0x811c9dc5;
  for(final c in messageId.codeUnits){h^=c;h=(h*0x01000193)&0xffffffff;}
  return (h&0x0fffffff)*4+reminder;
}

/// Times of the reminders of an immediate message.
List<DateTime> reminderTimes(DateTime notifiedAt)=>[
  for(var i=1;i<=reminderCount;i++)notifiedAt.add(reminderInterval*i)];

/// Answer recorded by a notification action, waiting to be queued in the
/// Outbox by the application (one JSON object per line).
class PendingAnswer {
  final String id, eventId, messageId, deviceId, status; final DateTime time;
  const PendingAnswer({required this.id,required this.eventId,required this.messageId,required this.deviceId,
    required this.status,required this.time});

  String toLine()=>jsonEncode({'id':id,'event_id':eventId,'message_id':messageId,'actor_id':deviceId,
    'status':status,'time':time.toUtc().toIso8601String()});

  Map<String,dynamic> toAck()=>{'id':id,'event_id':eventId,'message_id':messageId,'actor_id':deviceId,
    'status':status,'time':time.toUtc().toIso8601String()};

  static List<PendingAnswer> parseLines(String text){
    final out=<PendingAnswer>[];
    for(final line in const LineSplitter().convert(text)){
      if(line.trim().isEmpty)continue;
      try{
        final j=jsonDecode(line) as Map<String,dynamic>;
        out.add(PendingAnswer(id:j['id'] as String,eventId:j['event_id'] as String,messageId:j['message_id'] as String,
          deviceId:j['actor_id'] as String,status:j['status'] as String,time:DateTime.parse(j['time'] as String)));
      }catch(_){/* a damaged line is skipped, the others are kept */}
    }
    return out;
  }
}
