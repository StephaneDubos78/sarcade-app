/// Messages as on WhatsApp (vault note « Messages façon WhatsApp », decisions
/// of 23 October 2026): status ticks of the messages sent from this device,
/// automatic « read », opening on the first unread message.
library;

import 'message.dart';

/// ⏱ waiting on the device, ✓ sent (reached the server), ✓✓ grey received,
/// ✓✓ blue read.
enum SentStatus { pending, sent, received, read }

/// Accepting or refusing a message implies it was read.
const _readStatuses={'read','accepted','rejected'};

/// Status of a message sent by [senderId], from the acknowledgements of the
/// other participants. Several recipients (group, broadcast): received or
/// read as soon as one of them did, with the number of readers shown aside.
SentStatus sentStatus({required bool pending,required String senderId,required Iterable<SarcadeAck> acks}){
  if(pending)return SentStatus.pending;
  final others=acks.where((a)=>a.actorId!=senderId);
  if(others.any((a)=>_readStatuses.contains(a.status)))return SentStatus.read;
  if(others.isNotEmpty)return SentStatus.received;
  return SentStatus.sent;
}

/// Participants who read the message (shown as « lu par N » for groups).
int readersCount(String senderId,Iterable<SarcadeAck> acks)=>
  acks.where((a)=>a.actorId!=senderId&&_readStatuses.contains(a.status)).map((a)=>a.actorId).toSet().length;

/// A received message shown on screen is acknowledged « read » once, unless
/// this device already read, accepted or refused it.
bool needsAutoRead({required SarcadeMessage message,required String deviceId,required Iterable<SarcadeAck> acks}){
  if(message.senderId==deviceId)return false;
  return !acks.any((a)=>a.actorId==deviceId&&_readStatuses.contains(a.status));
}

/// Index where the screen opens: first unread message (under the « N
/// messages non lus » separator), or null to open at the bottom.
int? firstUnreadIndex(List<SarcadeMessage> shown,Set<String> unread){
  for(var i=0;i<shown.length;i++){if(unread.contains(shown[i].id))return i;}
  return null;
}
