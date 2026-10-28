import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../platform/platform_services.dart';
class RealtimeEvent {final String type;final Map<String,dynamic> data;const RealtimeEvent(this.type,this.data);}

/// WebSocket of the event, reconnected automatically after a network loss
/// (test of 23 Oct 2026: after airplane mode the channel stayed closed and
/// the status kept showing « Connecté »).
class RealtimeService {
 WebSocketChannel? _channel; StreamSubscription? _sub; Timer? _retry; Uri? _uri; bool _closing=false;
 /// Liveness (26 Oct 2026: a channel stayed open in the browser after a
 /// server restart, positions stopped until F5): « ping » every 30 s; once
 /// the server has answered one « pong », 90 s without anything closes and
 /// reopens the channel. Servers without pong are never timed out.
 static const pingEvery=Duration(seconds:30), silenceLimit=Duration(seconds:90);
 Timer? _ping; DateTime _lastIn=DateTime.now(); bool _pongSupported=false;
 /// Emitted after each (re)opening: the page reloads what it may have missed.
 static const reconnectedType='_reconnected';
 /// Headers read at each (re)connection: the Access session may be renewed.
 Map<String,String> Function()? _headers;
 final _events=StreamController<RealtimeEvent>.broadcast();
 /// True once the channel is open, false as soon as it closes or fails.
 bool connected=false;
 static const retryDelay=Duration(seconds:10);
 Stream<RealtimeEvent> get events=>_events.stream;

 void connect(Uri uri,{Map<String,String> Function()? headers}){disconnect();_uri=uri;_headers=headers;_closing=false;_open();}

 void _open(){
   final uri=_uri; if(uri==null||_closing)return;
   try{
     final ch=openWebSocket(uri,_headers?.call()??const {}); _channel=ch;
     ch.ready.then((_){
       if(!identical(_channel,ch))return;
       connected=true; _lastIn=DateTime.now();
       _events.add(const RealtimeEvent(reconnectedType,{}));
       _ping?.cancel(); _ping=Timer.periodic(pingEvery,(_)=>_keepAlive(ch));
     }).catchError((_){_lost(ch);});
     _sub=ch.stream.listen((raw){
       connected=true; _lastIn=DateTime.now();
       final j=jsonDecode(raw as String) as Map<String,dynamic>;
       if(j['type']=='pong'){_pongSupported=true;return;}
       _events.add(RealtimeEvent(j['type'],j['data']));
     },onError:(_){_lost(ch);},onDone:(){_lost(ch);},cancelOnError:true);
   }catch(_){_lost(_channel);}
 }

 void _keepAlive(WebSocketChannel ch){
   if(!identical(_channel,ch))return;
   if(silent(DateTime.now(),_lastIn,_pongSupported)){try{ch.sink.close();}catch(_){} _lost(ch);return;}
   try{ch.sink.add('ping');}catch(_){_lost(ch);}
 }

 /// Dead channel: the server answers pings, yet nothing came for 90 s.
 static bool silent(DateTime now,DateTime lastIn,bool pongSupported)=>pongSupported&&now.difference(lastIn)>silenceLimit;

 void _lost(WebSocketChannel? ch){
   if(ch!=null&&!identical(_channel,ch))return;
   _ping?.cancel(); _ping=null;
   connected=false; _sub?.cancel(); _sub=null; _channel=null;
   if(_closing)return;
   _retry?.cancel(); _retry=Timer(retryDelay,_open);
 }

 /// Reconnect at once (network back, manual synchronisation).
 void reconnectNow(){if(!connected&&_channel==null&&_uri!=null&&!_closing){_retry?.cancel();_open();}}

 void disconnect(){_closing=true;_retry?.cancel();_ping?.cancel();_sub?.cancel();_sub=null;_channel?.sink.close();_channel=null;connected=false;}
 Future<void> dispose() async {disconnect();await _events.close();}
}
