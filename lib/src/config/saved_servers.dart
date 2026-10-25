/// Servers remembered on the device (vault note « Mémorisation des
/// serveurs », step 1, decisions of 23 October 2026): up to 10, remembered at
/// the first successful connection, with the last event and terminal
/// identifier of each, `https://app.sarcade.org` always offered.
library;

import 'dart:convert';

import 'app_config.dart' show defaultServerUrl;

const maxSavedServers=10;

class SavedServer {
  final String url, label; final String? lastEvent, lastDevice; final DateTime? lastUsed;
  const SavedServer({required this.url,required this.label,this.lastEvent,this.lastDevice,this.lastUsed});
  factory SavedServer.fromJson(Map<String,dynamic> j)=>SavedServer(url:'${j['url']}',label:'${j['label']??defaultLabel('${j['url']}')}',
    lastEvent:j['last_event'] as String?,lastDevice:j['last_device'] as String?,lastUsed:DateTime.tryParse('${j['last_used']??''}'));
  Map<String,dynamic> toJson()=>{'url':url,'label':label,if(lastEvent!=null)'last_event':lastEvent,if(lastDevice!=null)'last_device':lastDevice,
    if(lastUsed!=null)'last_used':lastUsed!.toUtc().toIso8601String()};
  SavedServer copyWith({String? url,String? label,String? lastEvent,String? lastDevice,DateTime? lastUsed})=>SavedServer(
    url:url??this.url,label:label??this.label,lastEvent:lastEvent??this.lastEvent,lastDevice:lastDevice??this.lastDevice,lastUsed:lastUsed??this.lastUsed);
  /// « app.sarcade.org », « 192.168.0.110:8000 ».
  String get shortAddress=>defaultLabel(url);
}

/// Address without scheme nor trailing slash, compared without case.
String serverKey(String url){
  var s=url.trim().toLowerCase();
  while(s.endsWith('/')){s=s.substring(0,s.length-1);}
  return s;
}

/// Default label: the address without « https:// ».
String defaultLabel(String url){
  final u=Uri.tryParse(url.trim());
  if(u==null||u.host.isEmpty)return url.trim();
  return u.hasPort?'${u.host}:${u.port}':u.host;
}

/// The list read from the device, with the public server always present.
List<SavedServer> parseSavedServers(String? stored){
  final out=<SavedServer>[];
  try{
    final raw=stored==null?const []:jsonDecode(stored) as List;
    for(final j in raw){if(j is Map)out.add(SavedServer.fromJson(Map<String,dynamic>.from(j)));}
  }catch(_){/* unreadable: start again from the default */}
  if(!out.any((s)=>serverKey(s.url)==serverKey(defaultServerUrl))){
    out.insert(0,SavedServer(url:defaultServerUrl,label:'SARCADE · ${defaultLabel(defaultServerUrl)}'));
  }
  return out;
}

String encodeSavedServers(List<SavedServer> list)=>jsonEncode([for(final s in list)s.toJson()]);

/// Remembers a successful connection to [url] (with the event and terminal
/// used, when known). Beyond [maxSavedServers], the server unused for the
/// longest time goes, never the public one nor [url].
List<SavedServer> rememberServer(List<SavedServer> list,String url,{String? eventId,String? deviceId,required DateTime now}){
  var clean=url.trim(); while(clean.endsWith('/')){clean=clean.substring(0,clean.length-1);}
  final key=serverKey(clean);
  final out=[...list];
  final i=out.indexWhere((s)=>serverKey(s.url)==key);
  if(i>=0){
    out[i]=out[i].copyWith(lastEvent:eventId,lastDevice:deviceId,lastUsed:now);
  }else{
    out.add(SavedServer(url:clean,label:defaultLabel(clean),lastEvent:eventId,lastDevice:deviceId,lastUsed:now));
  }
  while(out.length>maxSavedServers){
    final candidates=out.where((s)=>serverKey(s.url)!=key&&serverKey(s.url)!=serverKey(defaultServerUrl)).toList()
      ..sort((a,b)=>(a.lastUsed??DateTime(2000)).compareTo(b.lastUsed??DateTime(2000)));
    if(candidates.isEmpty)break;
    out.remove(candidates.first);
  }
  return out;
}

SavedServer? findServer(List<SavedServer> list,String url){
  final key=serverKey(url);
  for(final s in list){if(serverKey(s.url)==key)return s;}
  return null;
}

/// The public server stays offered; any other can be removed.
bool canRemoveServer(SavedServer s)=>serverKey(s.url)!=serverKey(defaultServerUrl);
