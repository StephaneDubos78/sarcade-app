import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
class RealtimeEvent {final String type;final Map<String,dynamic> data;const RealtimeEvent(this.type,this.data);}
class RealtimeService {
 WebSocketChannel? _channel; final _events=StreamController<RealtimeEvent>.broadcast();
 Stream<RealtimeEvent> get events=>_events.stream;
 void connect(Uri uri){disconnect();_channel=WebSocketChannel.connect(uri);_channel!.stream.listen((raw){final j=jsonDecode(raw as String) as Map<String,dynamic>;_events.add(RealtimeEvent(j['type'],j['data']));},onError:_events.addError);}
 void disconnect(){_channel?.sink.close();_channel=null;}
 Future<void> dispose() async {disconnect();await _events.close();}
}
