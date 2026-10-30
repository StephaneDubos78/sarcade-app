/// One notification per message, one per distress (card « Détresse, une
/// seule notification », 30 Oct 2026, 12 h 45). Pure code.
///
/// A) a message has one notification, whatever the path that brings it
///    (realtime, synchronisation, wake-up): its key is its identifier;
/// B) a distress is one notification that its reminders update;
/// C) the « Fin de détresse » replaces the notification of the distress:
///    both share the key of the sender, [sosKey];
/// D) same key on every platform: Android and iPhone (notification
///    identifier, APNs collapse id), web (tag). The server computes the
///    same key for the wake-up (sarcade-server, wakeup/service.py).
library;

import '../models/message.dart';

bool _isSos(String body)=>body.trimLeft().startsWith('🆘');
bool _isSosEnd(String body){
  final b=body.trim().toLowerCase();
  return b.startsWith('fin de détresse')||b.startsWith('end of distress');
}

/// Key of the distress notifications of [senderId] in [eventId]: no
/// callsign in it (FNV-1a 32 bits, as on the server).
String sosKey(String eventId,String senderId){
  var h=0x811c9dc5;
  for(final c in '$eventId|$senderId'.codeUnits){h^=c;h=(h*0x01000193)&0xffffffff;}
  return 'sos-${h.toRadixString(16).padLeft(8,'0')}';
}

/// True for a distress (immediate « 🆘 ») or its end, sent to everyone.
bool isDistressNotification({required String body,required String priority,required List<String> recipientIds})=>
  recipientIds.isEmpty&&((priority=='immediate'&&_isSos(body))||_isSosEnd(body));

/// Key of the notification of a message.
String notificationKey({required String eventId,required String messageId,required String senderId,
    required String body,required String priority,required List<String> recipientIds})=>
  isDistressNotification(body:body,priority:priority,recipientIds:recipientIds)?sosKey(eventId,senderId):messageId;

/// Key of the notification of [m].
String messageNotificationKey(SarcadeMessage m)=>notificationKey(eventId:m.eventId,messageId:m.id,senderId:m.senderId,
  body:m.body,priority:m.priority,recipientIds:m.recipientIds);
