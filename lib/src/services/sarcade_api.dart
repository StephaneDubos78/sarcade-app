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
  Future<SarcadeSharedFile> uploadFile(String eventId,String senderId,String name,String mimeType,List<int> bytes,{String? fileId}) async {
    final req=http.MultipartRequest('POST',Uri.parse('$baseUrl/api/v0.1/events/$eventId/files'))
      ..fields['sender_id']=senderId
      ..fields['mime_type']=mimeType
      ..files.add(http.MultipartFile.fromBytes('file',bytes,filename:name,contentType:null));
    if(fileId!=null)req.fields['file_id']=fileId;
    final streamed=await _client.send(req); final body=await streamed.stream.bytesToString();
    if(streamed.statusCode!=201&&streamed.statusCode!=200) throw SarcadeHttpException('file_upload',streamed.statusCode,body);
    return SarcadeSharedFile.fromJson(jsonDecode(body));
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
  Future<Map<String,dynamic>> event(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId'));
    if(r.statusCode!=200) throw SarcadeHttpException('event',r.statusCode);
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
  /// Routes with ordered waypoints, lengths and passages.
  Future<List<Map<String,dynamic>>> routes(String eventId) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/routes'));
    if(r.statusCode!=200) throw SarcadeHttpException('routes',r.statusCode);
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
