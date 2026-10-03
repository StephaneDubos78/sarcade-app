class SarcadeSharedFile {
  final String id,eventId,senderId,name,mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  const SarcadeSharedFile({required this.id,required this.eventId,required this.senderId,required this.name,required this.mimeType,required this.sizeBytes,required this.createdAt});
  factory SarcadeSharedFile.fromJson(Map<String,dynamic> j)=>SarcadeSharedFile(
    id:j['id'],eventId:j['event_id'],senderId:j['sender_id'],name:j['name'],
    mimeType:j['mime_type']??'application/octet-stream',sizeBytes:j['size_bytes']??0,
    createdAt:DateTime.parse(j['created_at']));
}
