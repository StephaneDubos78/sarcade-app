/// Unread messages of the terminal (pastille on the Messages button).
library;

import 'comm_group.dart';
import 'message.dart';

/// Messages addressed to [deviceId] (broadcast, its groups, direct), written
/// by someone else, and not yet seen on the messages screen.
List<SarcadeMessage> unreadMessages({required Iterable<SarcadeMessage> messages,required Set<String> seen,
    required String deviceId,required Map<String,CommGroup> groups}){
  return [for(final m in messages)
    if(m.senderId!=deviceId&&!seen.contains(m.id)&&addressedTo(m.recipientIds,deviceId,groups))m];
}

/// Urgent or immediate among them: the pastille turns red.
bool anyUrgent(Iterable<SarcadeMessage> messages)=>messages.any((m)=>m.priority=='urgent'||m.priority=='immediate');

/// Desktop and web on a computer: a physical keyboard, Enter sends.
/// Phones and tablets keep Enter for a new line and send with the button.
bool enterSends(String targetPlatform)=>const {'windows','linux','macOS'}.contains(targetPlatform);
