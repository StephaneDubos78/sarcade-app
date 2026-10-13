/// A file referenced by a message. The bytes travel through the files API.
class SarcadeAttachment {
 final String fileId,name,mimeType; final int sizeBytes;
 const SarcadeAttachment({required this.fileId,required this.name,required this.mimeType,required this.sizeBytes});
 bool get isImage=>mimeType.startsWith('image/');
 factory SarcadeAttachment.fromJson(Map j)=>SarcadeAttachment(
   fileId:j['file_id'] as String,name:(j['name']??'photo.jpg') as String,
   mimeType:(j['mime_type']??'application/octet-stream') as String,sizeBytes:(j['size_bytes'] as num?)?.toInt()??0);
 Map<String,dynamic> toJson()=>{'file_id':fileId,'name':name,'mime_type':mimeType,'size_bytes':sizeBytes};
}
class SarcadeMessage {
 final String id,eventId,senderId,priority,body; final List<String> recipientIds; final DateTime createdAt;
 final List<SarcadeAttachment> attachments;
 const SarcadeMessage({required this.id,required this.eventId,required this.senderId,required this.recipientIds,required this.priority,required this.body,required this.createdAt,this.attachments=const []});
 factory SarcadeMessage.fromJson(Map<String,dynamic> j)=>SarcadeMessage(id:j['id'],eventId:j['event_id'],senderId:j['sender_id'],recipientIds:List<String>.from(j['recipient_ids']??[]),priority:j['priority']??'routine',body:j['body'],createdAt:DateTime.parse(j['created_at']),
   attachments:[for(final a in (j['attachments'] as List?)??const []) if(a is Map) SarcadeAttachment.fromJson(a)]);
 Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'sender_id':senderId,'recipient_ids':recipientIds,'priority':priority,'body':body,'created_at':createdAt.toUtc().toIso8601String(),
   if(attachments.isNotEmpty)'attachments':[for(final a in attachments)a.toJson()]};
}
class SarcadeAck {
 final String id,eventId,messageId,actorId,status; final DateTime time;
 const SarcadeAck({required this.id,required this.eventId,required this.messageId,required this.actorId,required this.status,required this.time});
 factory SarcadeAck.fromJson(Map<String,dynamic> j)=>SarcadeAck(id:j['id'],eventId:j['event_id'],messageId:j['message_id'],actorId:j['actor_id'],status:j['status'],time:DateTime.parse(j['time']));
 Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'message_id':messageId,'actor_id':actorId,'status':status,'time':time.toUtc().toIso8601String()};
}
class LogbookEntry {
 final int seq; final String kind,summary; final String? objectId,actorId; final DateTime time;
 const LogbookEntry({required this.seq,required this.kind,required this.summary,required this.time,this.objectId,this.actorId});
 factory LogbookEntry.fromJson(Map<String,dynamic> j)=>LogbookEntry(seq:j['seq'],kind:j['kind'],objectId:j['object_id'],actorId:j['actor_id'],summary:j['summary'],time:DateTime.parse(j['time']));
}
