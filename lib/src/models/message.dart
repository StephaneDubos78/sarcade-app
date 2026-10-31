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
 /// Deleted for everyone (by its author, or by the PCO): text and photos gone.
 final bool deleted, deletedByPco;
 /// Quoted message (« Répondre », 31 Oct 2026).
 final String? replyTo;
 const SarcadeMessage({this.replyTo,required this.id,required this.eventId,required this.senderId,required this.recipientIds,required this.priority,required this.body,required this.createdAt,this.attachments=const [],this.deleted=false,this.deletedByPco=false});
 factory SarcadeMessage.fromJson(Map<String,dynamic> j)=>SarcadeMessage(id:j['id'],eventId:j['event_id'],senderId:j['sender_id'],recipientIds:List<String>.from(j['recipient_ids']??[]),priority:j['priority']??'routine',body:(j['body']??'') as String,createdAt:DateTime.parse(j['created_at']),
   attachments:[for(final a in (j['attachments'] as List?)??const []) if(a is Map) SarcadeAttachment.fromJson(a)],
   deleted:j['deleted']==true,deletedByPco:j['deleted_by_pco']==true,
   replyTo:j['reply_to'] is String&&(j['reply_to'] as String).isNotEmpty?j['reply_to'] as String:null);
 Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'sender_id':senderId,'recipient_ids':recipientIds,'priority':priority,'body':body,'created_at':createdAt.toUtc().toIso8601String(),
   if(attachments.isNotEmpty)'attachments':[for(final a in attachments)a.toJson()],
   if(deleted)'deleted':true,if(deletedByPco)'deleted_by_pco':true,if(replyTo!=null)'reply_to':replyTo};
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

/// Priorities known by the server (revue d'ergonomie n° 35): never the
/// technical name; `normal` and any unknown value read « Routine »;
/// `distress` reads « Détresse », in red like « Immédiat ».
const knownPriorities=['routine','urgent','immediate','distress'];
String priorityKey(String p)=>'priority.${knownPriorities.contains(p)?p:'routine'}';
bool priorityRaised(String p)=>p=='urgent'||p=='immediate'||p=='distress';
bool priorityRed(String p)=>p=='immediate'||p=='distress';

/// Quote shown above a reply and in the field while answering: author and
/// the start of the text (« Photo » without text, « Message supprimé »).
({String author,String text,bool deleted}) quoteOf(SarcadeMessage? original,{required String deletedText,required String photoText,required String missingText}){
  if(original==null)return (author:'',text:missingText,deleted:true);
  if(original.deleted)return (author:original.senderId,text:deletedText,deleted:true);
  final t=original.body.trim().replaceAll(RegExp(r'\s+'),' ');
  final text=t.isEmpty?photoText:(t.length>90?'${t.substring(0,87)}…':t);
  return (author:original.senderId,text:text,deleted:false);
}
