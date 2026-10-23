import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
class RealtimeEvent {final String type;final Map<String,dynamic> data;const RealtimeEvent(this.type,this.data);}

/// WebSocket of the event, reconnected automatically after a network loss
/// (test of 23 Oct 2026: after airplane mode the channel stayed closed and
/// the status kept showing « Connecté »).
class RealtimeService {
 WebSocketChannel? _channel; StreamSubscription? _sub; Timer? _retry; Uri? _uri; bool _closing=false;
 final _events=StreamController<RealtimeEvent>.broadcast();
 /// True once the channel is open, false as soon as it closes or fails.
 bool connected=false;
 static const retryDelay=Duration(seconds:10);
 Stream<RealtimeEvent> get events=>_events.stream;

 void connect(Uri uri){disconnect();_uri=uri;_closing=false;_open();}

 void _open(){
   final uri=_uri; if(uri==null||_closing)return;
   try{
     final ch=WebSocketChannel.connect(uri); _channel=ch;
     ch.ready.then((_){if(identical(_channel,ch))connected=true;}).catchError((_){_lost(ch);});
     _sub=ch.stream.listen((raw){
       connected=true;
       final j=jsonDecode(raw as String) as Map<String,dynamic>;
       _events.add(RealtimeEvent(j['type'],j['data']));
     },onError:(_){_lost(ch);},onDone:(){_lost(ch);},cancelOnError:true);
   }catch(_){_lost(_channel);}
 }

 void _lost(WebSocketChannel? ch){
   if(ch!=null&&!identical(_channel,ch))return;
   connected=false; _sub?.cancel(); _sub=null; _channel=null;
   if(_closing)return;
   _retry?.cancel(); _retry=Timer(retryDelay,_open);
 }

 /// Reconnect at once (network back, manual synchronisation).
 void reconnectNow(){if(!connected&&_channel==null&&_uri!=null&&!_closing){_retry?.cancel();_open();}}

 void disconnect(){_closing=true;_retry?.cancel();_sub?.cancel();_sub=null;_channel?.sink.close();_channel=null;connected=false;}
 Future<void> dispose() async {disconnect();await _events.close();}
}
