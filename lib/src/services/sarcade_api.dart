import 'dart:convert';
import 'package:http/http.dart' as http;
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
  SarcadeApi({required this.baseUrl,http.Client? client}):_client=client??http.Client();
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
    if(r.statusCode!=200) throw Exception('sync_http_${r.statusCode}');
    return (jsonDecode(r.body) as List).map((e)=>Map<String,dynamic>.from(e)).toList();
  }

  Future<({List<Map<String,dynamic>> changes,String nextCursor})> changes(String eventId,int after) async {
    final r=await _client.get(Uri.parse('$baseUrl/api/v0.1/events/$eventId/sync/changes?after=$after'));
    if(r.statusCode!=200) throw Exception('changes_http_${r.statusCode}');
    final j=jsonDecode(r.body) as Map<String,dynamic>;
    return (changes:(j['changes'] as List).map((e)=>Map<String,dynamic>.from(e)).toList(),nextCursor:j['next_cursor'] as String);
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
  Future<Map<String,dynamic>> routing(String eventId,List<List<double>> points,String mode) async {
    final r=await _client.post(Uri.parse('$baseUrl/api/v0.1/routing'),headers:{'content-type':'application/json'},
      body:jsonEncode({'event_id':eventId,'points':points,'mode':mode}));
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
