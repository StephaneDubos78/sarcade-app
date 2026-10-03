import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/poi.dart';
import '../models/position.dart';
import '../models/message.dart';
import '../models/shared_file.dart';

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
  Future<SarcadeSharedFile> uploadFile(String eventId,String senderId,String name,String mimeType,List<int> bytes) async {
    final req=http.MultipartRequest('POST',Uri.parse('$baseUrl/api/v0.1/events/$eventId/files'))
      ..fields['sender_id']=senderId
      ..files.add(http.MultipartFile.fromBytes('file',bytes,filename:name,contentType:http.MediaType.parse(mimeType)));
    final streamed=await _client.send(req); final body=await streamed.stream.bytesToString();
    if(streamed.statusCode!=201) throw Exception('file_upload_http_${streamed.statusCode}:$body');
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
  Uri websocketUri(String eventId){final u=Uri.parse(baseUrl);return u.replace(scheme:u.scheme=='https'?'wss':'ws',path:'/api/v0.1/events/$eventId/ws');}
  void close()=>_client.close();
}
