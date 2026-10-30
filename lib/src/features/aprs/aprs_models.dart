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

/// « F4JPO » covers every SSID, « F4JPO-7 » only that station; « -0 » is
/// the bare callsign. Same rule as the server.
bool callsignMatches(String entry,String heard){
  final e=entry.toUpperCase().replaceAll(RegExp(r'-0$'),''), h=heard.toUpperCase().replaceAll(RegExp(r'-0$'),'');
  return e.contains('-')?e==h:h.split('-').first==e;
}

/// Last time a followed entry was heard among [heard] (callsign, time).
DateTime? lastHeard(String entry,Iterable<({String callsign,DateTime time})> heard){
  DateTime? best;
  for(final h in heard){if(callsignMatches(entry,h.callsign)&&(best==null||h.time.isAfter(best)))best=h.time;}
  return best;
}

/// Green dot: heard within the last hour.
bool heardRecently(DateTime? t,DateTime now)=>t!=null&&now.difference(t).inMinutes<60;

/// A name already used by another group (case and spaces ignored), as the
/// server refuses it (409).
bool groupNameTaken(String name,Iterable<Map<String,dynamic>> groups,{String? ownId}){
  String k(String s)=>s.split(RegExp(r'\s+')).where((w)=>w.isNotEmpty).join(' ').toLowerCase();
  return groups.any((g)=>g['id']!=ownId&&k('${g['name']}')==k(name));
}

/// Is [label] a radio amateur callsign (QRZ.com, aprs.fi links)?
bool looksLikeCallsign(String label){
  final c=label.trim().toUpperCase();
  return RegExp(r'^(?:[A-Z]{1,2}[0-9]|[0-9][A-Z]|[A-Z][0-9][A-Z]?)[0-9]?[A-Z]{1,4}(-[A-Z0-9]{1,2})?$').hasMatch(c)&&RegExp(r'[0-9]').hasMatch(c);
}
String qrzUrl(String callsign)=>'https://www.qrz.com/db/${Uri.encodeComponent(callsign.trim().toUpperCase().split('-').first)}';
String aprsFiUrl(String callsign)=>'https://aprs.fi/#!call=a%2F${Uri.encodeComponent(callsign.trim().toUpperCase())}';
