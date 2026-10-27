/// APRS settings of an event, as the PCO screen edits them.
library;

/// Callsign as typed: trimmed, upper case. « F4JPO » covers every SSID,
/// « F4JPO-7 » only that station. Same rule as the server (aprs/callsigns.py).
String? cleanCallsign(String raw){
  final c=raw.trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{1,9}(-[A-Z0-9]{1,2})?$').hasMatch(c)?c:null;
}

/// Callsigns from a free text (spaces, commas, new lines); the invalid ones
/// are returned apart so the screen can name them.
({List<String> valid,List<String> invalid}) parseCallsigns(String text){
  final valid=<String>[], invalid=<String>[];
  for(final part in text.split(RegExp(r'[\s,;]+'))){
    if(part.isEmpty)continue;
    final c=cleanCallsign(part);
    if(c==null){invalid.add(part);}else if(!valid.contains(c)){valid.add(c);}
  }
  return (valid:valid,invalid:invalid);
}

List<String> stringList(Object? v)=>v is List?v.map((e)=>'$e').toList():<String>[];

/// « connecté », « activé, non connecté », « désactivé » for one link.
String linkState(Map<String,dynamic>? link){
  if(link==null||link['enabled']!=true)return 'off';
  return link['connected']==true?'connected':'waiting';
}
