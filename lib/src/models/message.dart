class SarcadeMessage {
 final String id,eventId,senderId,priority,body; final List<String> recipientIds; final DateTime createdAt;
 const SarcadeMessage({required this.id,required this.eventId,required this.senderId,required this.recipientIds,required this.priority,required this.body,required this.createdAt});
 factory SarcadeMessage.fromJson(Map<String,dynamic> j)=>SarcadeMessage(id:j['id'],eventId:j['event_id'],senderId:j['sender_id'],recipientIds:List<String>.from(j['recipient_ids']??[]),priority:j['priority']??'routine',body:j['body'],createdAt:DateTime.parse(j['created_at']));
 Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'sender_id':senderId,'recipient_ids':recipientIds,'priority':priority,'body':body,'created_at':createdAt.toUtc().toIso8601String()};
}
class SarcadeAck {
 final String id,eventId,messageId,actorId,status; final DateTime time;
 const SarcadeAck({required this.id,required this.eventId,required this.messageId,required this.actorId,required this.status,required this.time});
 Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'message_id':messageId,'actor_id':actorId,'status':status,'time':time.toUtc().toIso8601String()};
}
