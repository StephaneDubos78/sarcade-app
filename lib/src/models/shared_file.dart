class SarcadeSharedFile {
  final String id,eventId,senderId,name,mimeType,folder;
  final int sizeBytes;
  final DateTime createdAt;
  const SarcadeSharedFile({required this.id,required this.eventId,required this.senderId,required this.name,required this.mimeType,required this.sizeBytes,required this.createdAt,this.folder='divers'});
  factory SarcadeSharedFile.fromJson(Map<String,dynamic> j)=>SarcadeSharedFile(
    id:j['id'],eventId:(j['event_id'] as String?)??'',senderId:(j['sender_id'] as String?)??'',name:j['name'],
    mimeType:j['mime_type']??'application/octet-stream',sizeBytes:j['size_bytes']??0,
    createdAt:DateTime.parse(j['created_at']),folder:(j['folder'] as String?)??'divers');
  bool get isImage=>mimeType.startsWith('image/');
}

/// Folders by use (« Écran Fichiers enrichi », 28 Oct 2026).
const fileFolders=['consignes','cartes','photos','fiches','divers'];

/// Files matching a search, in a folder (null: all), most recent first.
List<SarcadeSharedFile> filterFiles(Iterable<SarcadeSharedFile> files,{String query='',String? folder}){
  final q=query.trim().toLowerCase();
  return files.where((f)=>(folder==null||f.folder==folder)&&(q.isEmpty||f.name.toLowerCase().contains(q)||f.senderId.toLowerCase().contains(q)))
    .toList()..sort((a,b)=>b.createdAt.compareTo(a.createdAt));
}
