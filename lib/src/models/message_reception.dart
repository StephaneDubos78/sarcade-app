/// Reception of a message addressed to the terminal.
library;

/// Messages older than this are caught up silently (device off for a long
/// time, reinstallation): they stay in the list but do not ring.
const notifyMaxAge=Duration(hours:12);

/// A message notifies on its first arrival only, whether it came through the
/// realtime channel or the synchronisation, and only while it is recent.
bool shouldNotifyMessage({required bool alreadyReceived,required DateTime createdAt,required DateTime now}){
  if(alreadyReceived)return false;
  return now.difference(createdAt)<=notifyMaxAge;
}
