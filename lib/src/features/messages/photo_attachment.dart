/// Photos sent in messages: pure helpers, testable without Flutter.
library;

/// Above this size a photo is refused before upload (server limit is 25 MB).
const maxPhotoBytes=10*1024*1024;

/// Pickers do not always report a type (desktop, some browsers).
String photoMimeType(String? reported,String name){
  if(reported!=null&&reported.startsWith('image/'))return reported.toLowerCase();
  final n=name.toLowerCase();
  if(n.endsWith('.png'))return 'image/png';
  if(n.endsWith('.webp'))return 'image/webp';
  if(n.endsWith('.gif'))return 'image/gif';
  if(n.endsWith('.heic')||n.endsWith('.heif'))return 'image/heic';
  return 'image/jpeg';
}

/// Readable, sortable name: photo-20261010-143205.jpg (local time).
String photoFileName(DateTime t,String mimeType){
  final l=t.toLocal();
  String two(int v)=>v.toString().padLeft(2,'0');
  final ext=switch(mimeType){'image/png'=>'png','image/webp'=>'webp','image/gif'=>'gif','image/heic'=>'heic',_=>'jpg'};
  return 'photo-${l.year}${two(l.month)}${two(l.day)}-${two(l.hour)}${two(l.minute)}${two(l.second)}.$ext';
}

/// Outbox operations that can be sent now: a message waits until its photos
/// are on the server, everything else (positions, ACK, map) goes through.
List<Map<String,dynamic>> readyOperations(List<Map<String,dynamic>> ops,Set<String> pendingFileIds){
  if(pendingFileIds.isEmpty)return ops;
  return ops.where((op){
    if(op['object_type']!='message')return true;
    final payload=op['payload'];
    final atts=payload is Map?payload['attachments']:null;
    if(atts is! List)return true;
    return !atts.any((a)=>a is Map&&pendingFileIds.contains(a['file_id']));
  }).toList();
}
