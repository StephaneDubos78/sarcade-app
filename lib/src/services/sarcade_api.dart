import 'dart:convert';
import 'package:http/http.dart' as http;
import '../access/access_manager.dart';
import '../models/poi.dart';
import '../models/position.dart';
import '../models/message.dart';
import '../models/shared_file.dart';
import '../models/reference_site.dart';

/// HTTP refusal from the server, with its status for retry decisions.
class SarcadeHttpException implements Exception {
  final String operation; final int statusCode; final String body;
  const SarcadeHttpException(this.operation,this.statusCode,[this.body='']);
  /// 4xx except timeout and rate limit: retrying the same request cannot succeed.
  bool get isPermanent=>statusCode>=400&&statusCode<500&&statusCode!=408&&statusCode!=429;
  @override String toString()=>'${operation}_http_$statusCode${body.isEmpty?'':':$body'}';
}

class SarcadeApi {
  final String baseUrl; final http.Client _client;
  SarcadeApi({required this.baseUrl,http.Client? client}):_client=client??AccessHttpClient();
  /// Headers of the Cloudflare Access session, for the real-time channel.
  Map<String,String> realtimeHeaders()=>AccessManager.instance.headersFor(Uri.parse(baseUrl));
  Future<List<SarcadePosition>> latestPositions(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/positions/latest'));
    if(r.statusCode!=200) throw Exception('positions_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>SarcadePosition.fromJson(e)).toList();
  }
  Future<List<SarcadePosition>> positionHistory(String eventId,String deviceId,{int limit=500}) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/devices/$deviceId/positions?limit=$limit'));
    if(r.statusCode!=200) throw Exception('history_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>SarcadePosition.fromJson(e)).toList();
  }

  Future<List<SarcadePoi>> pois(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/pois'));
    if(r.statusCode!=200) throw Exception('pois_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>SarcadePoi.fromJson(e)).toList();
  }
  Future<List<ReferenceSite>> referenceSites({String? category,String? query}) async {
    final params=<String,String>{};
    if(category!=null&&category.isNotEmpty)params['category']=category;
    if(query!=null&&query.trim().isNotEmpty)params['q']=query.trim();
    final uri=Uri.parse('$baseUrl/api/v0.1/reference-sites').replace(queryParameters:params.isEmpty?null:params);
    final r=await _client.get(uri);
    if(r.statusCode!=200) throw Exception('reference_sites_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>ReferenceSite.fromJson(Map<String,dynamic>.from(e))).toList();
  }

  Future<void> sendPosition(SarcadePosition p) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/positions'),headers:{'content-type':'application/json'},body:jsonEncode(p.toJson()));
    if(r.statusCode!=202) throw Exception('position_http_${r.statusCode}');
  }
  Future<List<Map<String,dynamic>>> sync(List<Map<String,dynamic>> operations) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/sync'),headers:{'content-type':'application/json'},body:jsonEncode(operations));
    if(r.statusCode!=200) throw SarcadeHttpException('sync',r.statusCode,r.body);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e)).toList();
  }

  Future<({List<Map<String,dynamic>> changes,String nextCursor})> changes(String eventId,int after) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/sync/changes?after=$after'));
    if(r.statusCode!=200) throw SarcadeHttpException('changes',r.statusCode,r.body);
    final j=jsonDecode(r.body) as Map<String,dynamic>;
    return (changes:(j['changes'] as List).map((e)=>Map<String,dynamic>.from(e)).toList(),nextCursor:j['next_cursor'] as String);
  }

  /// Events of the server, newest first, closed ones hidden unless asked.
  Future<List<Map<String,dynamic>>> events({bool includeClosed=false}) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events${includeClosed?'?include_closed=true':''}'));
    if(r.statusCode!=200) throw SarcadeHttpException('events',r.statusCode,r.body);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }

  Future<List<SarcadeSharedFile>> files(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/files'));
    if(r.statusCode!=200) throw Exception('files_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>SarcadeSharedFile.fromJson(e)).toList();
  }
  /// [fileId], chosen by the client, makes a retried upload idempotent
  /// (the server answers 200 with the stored file).
  Future<SarcadeSharedFile> uploadFile(String eventId,String senderId,String name,String mimeType,List<int> bytes,{String? fileId,String? folder}) async {
    final req=http.MultipartRequest('POST',Uri.parse('$baseUrl/api/v0.1/events/$eventId/files'))
      ..fields['sender_id']=senderId
      ..fields['mime_type']=mimeType
      ..files.add(http.MultipartFile.fromBytes('file',bytes,filename:name,contentType:null));
    if(fileId!=null)req.fields['file_id']=fileId;
    if(folder!=null)req.fields['folder']=folder;
    final streamed=await _client.send(req); final body=await streamed.stream.bytesToString();
    if(streamed.statusCode!=201&&streamed.statusCode!=200) throw SarcadeHttpException('file_upload',streamed.statusCode,body);
    return SarcadeSharedFile.fromJson(jsonDecode(body));
  }
  /// « Personnel » folder of the person (email checked by Cloudflare
  /// Access): files, space used and quota; null when not available.
  Future<({List<SarcadeSharedFile> files,int used,int quota,List<String> folders})?> personalFiles() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/me/files'));
    if(r.statusCode!=200)return null;
    final j=jsonDecode(r.body) as Map;
    return (files:[for(final f in (j['files'] as List))SarcadeSharedFile.fromJson(Map<String,dynamic>.from(f as Map))],
      used:(j['used_bytes'] as num).toInt(),quota:(j['quota_bytes'] as num).toInt(),
      folders:[for(final f in (j['folders'] as List?)??const [])'$f']);
  }
  /// Event files and folders (« Fichiers : sous-dossiers »); an older server
  /// answers the bare list, folders then come from the files.
  Future<({List<SarcadeSharedFile> files,List<String> folders})> filesWithFolders(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/files?with_folders=true'));
    if(r.statusCode!=200) throw SarcadeHttpException('files',r.statusCode,r.body);
    final j=jsonDecode(r.body);
    if(j is List)return (files:[for(final e in j)SarcadeSharedFile.fromJson(Map<String,dynamic>.from(e as Map))],folders:const <String>[]);
    final m=j as Map;
    return (files:[for(final e in (m['files'] as List))SarcadeSharedFile.fromJson(Map<String,dynamic>.from(e as Map))],
      folders:[for(final f in (m['folders'] as List?)??const [])'$f']);
  }
  /// Folders: [personal] for « Personnel », else the event.
  String _filesBase(String? eventId)=>eventId==null?'$baseUrl/api/v0.1/me/files':'$baseUrl/api/v0.1/events/$eventId/files';
  Future<void> createFolder(String? eventId,String path,{String? actorId}) async {
    final r=await _client.post(Uri.parse('${_filesBase(eventId)}/folders'),headers:_json,body:jsonEncode({'path':path,'actor_id':?actorId}));
    if(r.statusCode!=201) throw SarcadeHttpException('folder_create',r.statusCode,r.body);
  }
  Future<void> moveFolder(String? eventId,String from,String to,{String? actorId}) async {
    final r=await _client.patch(Uri.parse('${_filesBase(eventId)}/folders'),headers:_json,body:jsonEncode({'from':from,'to':to,'actor_id':?actorId}));
    if(r.statusCode!=200) throw SarcadeHttpException('folder_move',r.statusCode,r.body);
  }
  Future<void> deleteFolder(String? eventId,String path,{String? actorId}) async {
    final r=await _client.delete(Uri.parse('${_filesBase(eventId)}/folders').replace(queryParameters:{'path':path,'actor_id':?actorId}));
    if(r.statusCode!=204) throw SarcadeHttpException('folder_delete',r.statusCode,r.body);
  }
  Future<void> moveFile(String? eventId,String fileId,{String? folder,String? name,String? actorId}) async {
    final r=await _client.patch(Uri.parse('${_filesBase(eventId)}/$fileId'),headers:_json,
      body:jsonEncode({'folder':?folder,'name':?name,'actor_id':?actorId}));
    if(r.statusCode!=200) throw SarcadeHttpException('file_move',r.statusCode,r.body);
  }
  Future<void> uploadPersonalFile(String name,List<int> bytes,{String? folder}) async {
    final req=http.MultipartRequest('POST',Uri.parse('$baseUrl/api/v0.1/me/files'))
      ..files.add(http.MultipartFile.fromBytes('file',bytes,filename:name));
    if(folder!=null&&folder.isNotEmpty)req.fields['folder']=folder;
    final streamed=await _client.send(req); final body=await streamed.stream.bytesToString();
    if(streamed.statusCode!=201) throw SarcadeHttpException('personal_upload',streamed.statusCode,body);
  }
  Future<List<int>> downloadPersonalFile(String fileId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/me/files/$fileId/content'));
    if(r.statusCode!=200) throw SarcadeHttpException('personal_download',r.statusCode,r.body);
    return r.bodyBytes;
  }
  Future<void> deletePersonalFile(String fileId) async {
    final r=await _client.delete(Uri.parse('$baseUrl/api/v0.1/me/files/$fileId'));
    if(r.statusCode!=204) throw SarcadeHttpException('personal_delete',r.statusCode,r.body);
  }
  Future<List<int>> downloadFile(String eventId,String fileId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/files/$fileId/content'));
    if(r.statusCode!=200) throw Exception('file_download_http_${r.statusCode}');
    return r.bodyBytes;
  }

  Future<List<SarcadeMessage>> messages(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/messages'));
    if(r.statusCode!=200) throw Exception('messages_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>SarcadeMessage.fromJson(e)).toList();
  }
  Future<List<LogbookEntry>> logbook(String eventId,{int after=0}) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/logbook?after=$after'));
    if(r.statusCode!=200) throw Exception('logbook_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>LogbookEntry.fromJson(e)).toList();
  }
  /// Every group of the event, archived included (the PCO sees everything).
  /// Channels of a model added to the event (« adrasec »: PCO, Équipes
  /// terrain, Transmissions, Logistique); returns how many were created.
  Future<int> addGroupTemplate(String eventId,String template) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/groups/defaults?template=$template'));
    if(r.statusCode!=200) throw SarcadeHttpException('group_template',r.statusCode,r.body);
    return ((jsonDecode(r.body) as Map)['created'] as num?)?.toInt()??0;
  }
  Future<List<Map<String,dynamic>>> groups(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/groups'));
    if(r.statusCode!=200) throw SarcadeHttpException('groups',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  // APRS (doc aprs-v0.1 of the server): callsign groups, event settings, status.
  Map<String,String> get _json=>const {'Content-Type':'application/json'};
  Future<List<Map<String,dynamic>>> aprsGroups() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/aprs/groups'));
    if(r.statusCode!=200) throw SarcadeHttpException('aprs_groups',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  /// Creates ([id] null) or updates a callsign group.
  Future<Map<String,dynamic>> saveAprsGroup({String? id,required String name,required List<String> callsigns,required String actorId}) async {
    final body=jsonEncode({'name':name,'callsigns':callsigns,'actor_id':actorId});
    final r=id==null
      ?await _client.post(Uri.parse('$baseUrl/api/v0.1/aprs/groups'),headers:_json,body:body)
      :await _client.put(Uri.parse('$baseUrl/api/v0.1/aprs/groups/$id'),headers:_json,body:body);
    if(r.statusCode!=200&&r.statusCode!=201) throw SarcadeHttpException('aprs_group',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  Future<void> deleteAprsGroup(String id) async {
    final r=await _client.delete(Uri.parse('$baseUrl/api/v0.1/aprs/groups/$id'));
    if(r.statusCode!=204&&r.statusCode!=404) throw SarcadeHttpException('aprs_group_delete',r.statusCode);
  }
  /// Smart TV (« Affichage sur Smart TV »): approve the code shown by the
  /// TV for this event; list and revoke the screens.
  Future<void> approveDisplay(String code,String eventId,{String? name}) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/tv/approve'),headers:_json,
      body:jsonEncode({'code':code,'event_id':eventId,if(name!=null&&name.trim().isNotEmpty)'name':name.trim()}));
    if(r.statusCode!=200) throw SarcadeHttpException('tv_approve',r.statusCode,r.body);
  }
  /// Default name of the TV showing [code] (« TV Samsung · 1920×1080 »);
  /// null when unknown, expired or with an older server.
  Future<String?> tvCodeName(String code) async {
    try{
      final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/tv/code/${Uri.encodeComponent(code)}'));
      if(r.statusCode!=200)return null;
      final n='${(jsonDecode(r.body) as Map)['name']??''}'.trim();
      return n.isEmpty?null:n;
    }catch(_){
      return null;
    }
  }
  /// « Renommer » a screen.
  Future<void> renameDisplay(String eventId,String displayId,String name) async {
    final r=await _client.put(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays/$displayId/name'),headers:_json,body:jsonEncode({'name':name}));
    if(r.statusCode!=200) throw SarcadeHttpException('display_name',r.statusCode,r.body);
  }
  /// « Identifier »: the TV shows its name in very large letters for 5 s.
  Future<void> identifyDisplay(String eventId,String displayId) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays/$displayId/identify'));
    if(r.statusCode!=200) throw SarcadeHttpException('display_identify',r.statusCode,r.body);
  }
  /// « Envoyer ma vue »: [view] null gives the TV its automatic framing back.
  /// [live] (« Suivre ma vue », lot 11): one logbook line for the whole follow.
  Future<void> sendDisplayView(String eventId,String displayId,Map<String,dynamic>? view,{bool live=false}) async {
    final r=await _client.put(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays/$displayId/view'),headers:_json,
      body:jsonEncode({'view':view,if(live)'live':true}));
    if(r.statusCode!=200) throw SarcadeHttpException('display_view',r.statusCode,r.body);
  }
  /// « Messages : afficher / masquer » of one screen, applied at once.
  Future<void> setDisplayMessages(String eventId,String displayId,bool messages) async {
    final r=await _client.put(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays/$displayId/messages'),headers:_json,body:jsonEncode({'messages':messages}));
    if(r.statusCode!=200) throw SarcadeHttpException('display_messages',r.statusCode,r.body);
  }
  /// Codes shown by TVs on the same network (same public address), for a
  /// PCO or an administrator; empty otherwise or with an older server.
  Future<List<String>> tvNearby() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/tv/nearby'));
    if(r.statusCode!=200)return const [];
    return [for(final d in jsonDecode(r.body) as List)'${(d as Map)['code']}'];
  }
  Future<List<Map<String,dynamic>>> displays(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays'));
    if(r.statusCode!=200) throw SarcadeHttpException('displays',r.statusCode,r.body);
    return [for(final d in jsonDecode(r.body) as List)Map<String,dynamic>.from(d as Map)];
  }
  /// « Retirer le bandeau SOS » of a screen: the person who paired it or an
  /// administrator (403 otherwise).
  Future<void> clearDisplayAlert(String eventId,String id) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays/$id/alert/clear'));
    if(r.statusCode!=200) throw SarcadeHttpException('display_alert_clear',r.statusCode,r.body);
  }
  Future<void> revokeDisplay(String eventId,String id) async {
    final r=await _client.delete(Uri.parse('$baseUrl/api/v0.1/events/$eventId/displays/$id'));
    if(r.statusCode!=204) throw SarcadeHttpException('display_revoke',r.statusCode,r.body);
  }

  /// Who the server sees (email checked by Cloudflare Access) and the
  /// rights it gives; null for an older server.
  Future<Map<String,dynamic>?> me() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/me'));
    if(r.statusCode!=200)return null;
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Personal settings kept by the server for the email checked by
  /// Cloudflare Access; null when the server cannot (no Access, older
  /// server): the device keeps them.
  Future<Map<String,dynamic>?> myPreferences() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/me/preferences'));
    if(r.statusCode!=200)return null;
    final j=Map<String,dynamic>.from(jsonDecode(r.body) as Map);
    return j['available']==true?Map<String,dynamic>.from(j['preferences'] as Map? ?? {}):null;
  }
  Future<bool> patchMyPreferences(Map<String,dynamic> patch) async {
    final r=await _client.patch(Uri.parse('$baseUrl/api/v0.1/me/preferences'),
      headers:{'content-type':'application/json'},body:jsonEncode(patch));
    return r.statusCode==200;
  }

  /// Paramètres › Diagnostic (lot 5): what the server sees of this device
  /// (public address, Cloudflare, email); null on an older server.
  Future<Map<String,dynamic>?> clientDiagnostics() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/diagnostics/client'));
    if(r.statusCode!=200)return null;
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Server block (PCO, administrators); 403 for the others.
  Future<Map<String,dynamic>> serverDiagnostics() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/diagnostics/server'));
    if(r.statusCode!=200) throw SarcadeHttpException('diagnostics',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }

  /// Wake-up of the devices (note « Réveil des appareils »).
  Future<Map<String,dynamic>> wakeupConfig() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/wakeup/config'));
    if(r.statusCode!=200) throw SarcadeHttpException('wakeup_config',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  Future<void> registerWakeToken(String eventId,String deviceId,String platform,String token) async {
    final r=await _client.put(Uri.parse('$baseUrl/api/v0.1/events/${Uri.encodeComponent(eventId)}/devices/${Uri.encodeComponent(deviceId)}/wakeup'),
      headers:{'content-type':'application/json'},body:jsonEncode({'platform':platform,'token':token}));
    if(r.statusCode!=200) throw SarcadeHttpException('wakeup_register',r.statusCode,r.body);
  }
  /// « Tester le réveil »: {sent, failed, removed}.
  Future<Map<String,dynamic>> testWakeup(String eventId,String deviceId) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/${Uri.encodeComponent(eventId)}/devices/${Uri.encodeComponent(deviceId)}/wakeup/test'));
    if(r.statusCode!=200) throw SarcadeHttpException('wakeup_test',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  Future<Map<String,dynamic>> aprsStatus() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/aprs/status'));
    if(r.statusCode!=200) throw SarcadeHttpException('aprs_status',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Callsigns actually followed by the event (groups + additions).
  Future<List<String>> followedCallsigns(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/aprs/callsigns'));
    if(r.statusCode!=200) throw SarcadeHttpException('aprs_callsigns',r.statusCode);
    return ((jsonDecode(r.body) as Map)['callsigns'] as List).map((e)=>'$e').toList();
  }
  /// APRS stations classified by hand, shared by the event: {device_id: fixed|mobile}.
  Future<Map<String,String>> aprsClasses(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/${Uri.encodeComponent(eventId)}/aprs/classes'));
    if(r.statusCode!=200) throw SarcadeHttpException('aprs_classes',r.statusCode);
    return ((jsonDecode(r.body) as Map)['classes'] as Map).map((k,v)=>MapEntry('$k','$v'));
  }
  /// [kind]: fixed, mobile or auto (removes the choice).
  Future<void> setAprsClass(String eventId,String deviceId,String actorId,String kind) async {
    final r=await _client.put(Uri.parse('$baseUrl/api/v0.1/events/${Uri.encodeComponent(eventId)}/aprs/classes/${Uri.encodeComponent(deviceId)}'),headers:_json,
      body:jsonEncode({'actor_id':actorId,'kind':kind}));
    if(r.statusCode!=200) throw SarcadeHttpException('aprs_class',r.statusCode,r.body);
  }
  Future<Map<String,dynamic>> event(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId'));
    if(r.statusCode!=200) throw SarcadeHttpException('event',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// New event (PCO), with the model that decides its modules (card
  /// « Séparer le Core et les modules », step 2): family, friends → Core;
  /// exercise, sater, mission → ADRASEC; race → Course.
  Future<Map<String,dynamic>> createEvent(String name,String kind) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events'),headers:_json,body:jsonEncode({'name':name,'kind':kind}));
    if(r.statusCode!=201) throw SarcadeHttpException('create_event',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Changes event settings (PCO); 409 when the event is closed, 422 refused.
  Future<Map<String,dynamic>> patchEventSettings(String eventId,String actorId,Map<String,dynamic> settings) async {
    final r=await _client.patch(Uri.parse('$baseUrl/api/v0.1/events/$eventId/settings'),headers:_json,
      body:jsonEncode({'actor_id':actorId,'settings':settings}));
    if(r.statusCode!=200) throw SarcadeHttpException('event_settings',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Addresses and places (Base Adresse Nationale through the server),
  /// nearest to [lat]/[lon] first; 503 when the service is unreachable.
  Future<Map<String,dynamic>> geocode(String q,{double? lat,double? lon}) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/geocode').replace(queryParameters:{
      'q':q,if(lat!=null)'lat':lat.toStringAsFixed(4),if(lon!=null)'lon':lon.toStringAsFixed(4)}));
    if(r.statusCode!=200) throw SarcadeHttpException('geocode',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Readable location of a point (« 800 m au nord de Plaisir ») and the
  /// nearest road when the server is online; 404 on an older server.
  Future<Map<String,dynamic>> describePlace(double lat,double lon) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/places/describe').replace(queryParameters:{
      'lat':lat.toStringAsFixed(5),'lon':lon.toStringAsFixed(5)}));
    if(r.statusCode!=200) throw SarcadeHttpException('places_describe',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Routes with ordered waypoints, lengths and passages.
  Future<List<Map<String,dynamic>>> routes(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/routes'));
    if(r.statusCode!=200) throw SarcadeHttpException('routes',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  /// Move orders of the PCO to the operators (404 on an older server).
  /// Default frequencies of the bearing tool (server setting, editable by
  /// the administrator): the raw JSON body {"signals":[…]}.
  Future<String> signalDefaults() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/signals/defaults'));
    if(r.statusCode!=200) throw SarcadeHttpException('signal_defaults',r.statusCode);
    return r.body;
  }
  Future<void> saveSignalDefaults(String body) async {
    final r=await _client.put(Uri.parse('$baseUrl/api/v0.1/signals/defaults'),headers:_json,body:body);
    if(r.statusCode!=200) throw SarcadeHttpException('signal_defaults',r.statusCode,r.body);
  }
  /// Devices of the event: platform, version and last contact (PCO list,
  /// operator sheet).
  Future<List<Map<String,dynamic>>> devices(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/devices'));
    if(r.statusCode!=200) throw SarcadeHttpException('devices',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  Future<List<Map<String,dynamic>>> moveOrders(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/move-orders'));
    if(r.statusCode!=200) throw SarcadeHttpException('move_orders',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  Future<List<Map<String,dynamic>>> roadClosures(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/road-closures'));
    if(r.statusCode!=200) throw SarcadeHttpException('road_closures',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  /// Itinerary computed by the server (Valhalla), avoiding closed roads.
  /// 422: no itinerary possible; 503: engine unavailable.
  Future<Map<String,dynamic>> routing(String eventId,List<List<double>> points,String mode,{int alternatives=0}) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/routing'),headers:{'content-type':'application/json'},
      body:jsonEncode({'event_id':eventId,'points':points,'mode':mode,if(alternatives>0)'alternatives':alternatives}));
    if(r.statusCode!=200) throw SarcadeHttpException('routing',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  Future<void> computeLegs(String eventId,String routeId) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/routes/$routeId/legs'));
    if(r.statusCode!=200) throw SarcadeHttpException('legs',r.statusCode);
  }
  /// The team reports an impracticable point; the PCO decides.
  Future<void> reportWaypoint(String eventId,String routeId,String actorId,String waypointId,String reason) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/routes/$routeId/reports'),headers:{'content-type':'application/json'},
      body:jsonEncode({'actor_id':actorId,'waypoint_id':waypointId,'reason':reason}));
    if(r.statusCode!=201) throw SarcadeHttpException('report',r.statusCode,r.body);
  }
  /// Last forecast of the event, kept by the server for offline use.
  Future<Map<String,dynamic>> eventWeather(String eventId,{bool compact=false}) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/weather${compact?'?compact=true':''}'));
    if(r.statusCode!=200) throw SarcadeHttpException('weather',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  Future<void> refreshWeather(String eventId) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/weather/refresh'));
    if(r.statusCode!=200) throw SarcadeHttpException('weather_refresh',r.statusCode,r.body);
  }
  Future<String> weatherBulletin(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/weather/bulletin'));
    if(r.statusCode!=200) throw SarcadeHttpException('bulletin',r.statusCode);
    final j=jsonDecode(r.body);
    return j is Map?'${j['text']??j['bulletin']??''}':'$j';
  }
  /// Forecast of a designated point.
  Future<Map<String,dynamic>> pointWeather(double lat,double lon) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/weather?lat=$lat&lon=$lon'));
    if(r.statusCode!=200) throw SarcadeHttpException('point_weather',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Base maps: built-in, custom, and offline packages of the server.
  Future<List<Map<String,dynamic>>> basemaps() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/basemaps'));
    if(r.statusCode!=200) throw SarcadeHttpException('basemaps',r.statusCode);
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
  }
  /// Itinerary engine of the server (Valhalla): {available, url}.
  Future<Map<String,dynamic>> routingStatus() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/routing/status'));
    if(r.statusCode!=200) throw SarcadeHttpException('routing_status',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Version of the road graph for navigation on the device.
  Future<Map<String,dynamic>> roadGraphInfo() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/routing/graph/info'));
    if(r.statusCode!=200) throw SarcadeHttpException('graph_info',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Settings of the organisation applied by the clients (navigation app).
  Future<Map<String,dynamic>> clientConfig() async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/clients/config'));
    if(r.statusCode!=200) throw SarcadeHttpException('client_config',r.statusCode);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Periodic contact of the device: the answer carries the PCO settings
  /// (low-bandwidth mode, tracking policy), the end of the event and the
  /// minimal client version.
  Future<Map<String,dynamic>> heartbeat(String eventId,String deviceId,Map<String,dynamic> body) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/events/$eventId/devices/${Uri.encodeComponent(deviceId)}/heartbeat'),
      headers:{'content-type':'application/json'},body:jsonEncode(body));
    if(r.statusCode!=200) throw SarcadeHttpException('heartbeat',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Minimal client version, asked at start (note « Mises à jour et sécurité »).
  Future<Map<String,dynamic>> clientCheck(String deviceId,String platform,String appVersion) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/clients/check'),headers:{'content-type':'application/json'},
      body:jsonEncode({'device_id':deviceId,'platform':platform,'app_version':appVersion}));
    if(r.statusCode!=200) throw SarcadeHttpException('client_check',r.statusCode,r.body);
    return Map<String,dynamic>.from(jsonDecode(r.body) as Map);
  }
  /// Bytes of a path of the server (client package, offline map package).
  Future<List<int>> download(String path) async {
    final r=await _client.get(Uri.parse('$baseUrl$path'));
    if(r.statusCode!=200) throw SarcadeHttpException('download',r.statusCode);
    return r.bodyBytes;
  }
  Uri websocketUri(String eventId){final u=Uri.parse(baseUrl);return u.replace(scheme:u.scheme=='https'?'wss':'ws',path:'/api/v0.1/events/$eventId/ws');}
  void close()=>_client.close();
}
