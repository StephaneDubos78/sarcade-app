import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../features/compass/compass_reading.dart';
import '../models/web_update.dart';

/// Browser builds return true here; installed apps return false.
const isWebPlatform=true;

/// Each browser tab is its own instance; Hive (IndexedDB) supports several.
Future<bool> acquireSingleInstance() async=>true;

/// A browser tab cannot end itself; nothing to do.
void quitApp(){}

/// Data lives in the browser's IndexedDB, kept when offline.
Future<void> initHiveStorage()=>Hive.initFlutter('sarcade');

/// The browser always provides the content of a picked file.
Future<List<int>?> readPickedFile(PlatformFile f) async=>f.bytes;

/// Saves bytes as a browser download and returns the file name.
Future<String> saveFile(String name,List<int> bytes,{bool temporary=false,String? mimeType}) async {
  final data=bytes is Uint8List?bytes:Uint8List.fromList(bytes);
  final blob=web.Blob([data.toJS].toJS,web.BlobPropertyBag(type:mimeType??'application/octet-stream'));
  final url=web.URL.createObjectURL(blob);
  final anchor=web.HTMLAnchorElement()..href=url..download=name;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return name;
}

/// A download is opened by the browser itself.
Future<void> openSavedFile(String path) async {}

const canOpenSavedFiles=false;

/// The web app is served by the SARCADE server: same origin as the API.
String? servingOrigin()=>web.window.location.origin;

/// A browser sends the session cookie with the WebSocket itself.
WebSocketChannel openWebSocket(Uri uri,Map<String,String> headers)=>WebSocketChannel.connect(uri);

/// Reloads the page: Cloudflare Access asks to sign in again if needed.
void reloadApp()=>web.window.location.reload();

/// Build published next to the web app (`sarcade_build.json`, written by the
/// CI), read past every cache; null when unreadable (offline, local build).
Future<({String? build,String? version})> fetchServedBuild() async {
  try{
    final url='sarcade_build.json?t=${DateTime.now().millisecondsSinceEpoch}';
    final r=await web.window.fetch(url.toJS,web.RequestInit(cache:'no-store',credentials:'include')).toDart;
    if(!r.ok)return (build:null,version:null);
    final json=jsonDecode((await r.text().toDart).toDart);
    return (build:parseServedBuild(json),version:parseServedVersion(json));
  }catch(_){return (build:null,version:null);}
}

/// « Mettre à jour »: drops the copies kept by the SARCADE service worker,
/// then reloads, so the new code is fetched from the server.
Future<void> reloadFresh() async {
  try{
    final keys=(await web.window.caches.keys().toDart).toDart;
    for(final k in keys){
      final name=k.toDart;
      if(name.startsWith('sarcade-shell'))await web.window.caches.delete(name).toDart;
    }
  }catch(_){}
  // Service workers left by older versions (the deprecated Flutter one
  // replaced the SARCADE one at every start): removed, the page registers
  // sarcade_sw.js again on load.
  try{
    final regs=(await web.window.navigator.serviceWorker.getRegistrations().toDart).toDart;
    for(final r in regs){await r.unregister().toDart;}
  }catch(_){}
  web.window.location.reload();
}
bool get browserOnline=>web.window.navigator.onLine;

/// Web Push subscription of this browser (note « Réveil des appareils »),
/// as the JSON the server expects; null when push is unavailable or the
/// notifications are not allowed. The SARCADE service worker shows the
/// notification when no SARCADE window is visible.
Future<String?> webPushSubscription(String publicKey) async {
  try{
    if(web.Notification.permission!='granted')return null;
    final reg=await web.window.navigator.serviceWorker.ready.toDart;
    var sub=await reg.pushManager.getSubscription().toDart;
    sub??=await reg.pushManager.subscribe(web.PushSubscriptionOptionsInit(userVisibleOnly:true,applicationServerKey:publicKey.toJS)).toDart;
    String key(String name){
      final buffer=sub!.getKey(name);
      if(buffer==null)throw StateError('no $name');
      return base64Url.encode(buffer.toDart.asUint8List()).replaceAll('=','');
    }
    return jsonEncode({'endpoint':sub.endpoint,'keys':{'p256dh':key('p256dh'),'auth':key('auth')}});
  }catch(e){
    debugPrint('SARCADE web push unavailable: $e');
    return null;
  }
}

/// Wake-up signals passed on by the SARCADE service worker to the open
/// windows ({sarcade: 'wake', data}), for « Tester le réveil ».
Stream<Map<String,dynamic>> webWakeSignals(){
  late final StreamController<Map<String,dynamic>> c;
  final listener=((web.MessageEvent e){
    final d=e.data.dartify();
    if(d is Map&&d['sarcade']=='wake'&&!c.isClosed){
      c.add(d['data'] is Map?Map<String,dynamic>.from(d['data'] as Map):<String,dynamic>{});
    }
  }).toJS;
  c=StreamController<Map<String,dynamic>>(
    onListen:(){try{web.window.navigator.serviceWorker.addEventListener('message',listener);}catch(_){}},
    onCancel:(){try{web.window.navigator.serviceWorker.removeEventListener('message',listener);}catch(_){}});
  return c.stream;
}

/// Asks the browser to keep the offline data (IndexedDB) instead of evicting
/// it when space runs low: an installed PCO may hold unsent messages.
/// Granted silently for installed apps in Chrome and Edge.
Future<bool> requestPersistentStorage() async {
  try{
    final storage=web.window.navigator.storage;
    if((await storage.persisted().toDart).toDart)return true;
    return (await storage.persist().toDart).toDart;
  }catch(_){return false;}
}


/// Compass of the browser: « deviceorientation » events. iPhone gives the
/// heading itself (webkitCompassHeading, after a permission asked on a tap);
/// Android Chrome gives an absolute orientation (360 − alpha). Degrees from
/// magnetic north, clockwise; nothing on a computer.
Future<Stream<double>?> compassHeadings() async {
  try{
    final doe=globalContext['DeviceOrientationEvent'];
    if(doe==null)return null;
    final o=doe as JSObject;
    if(o.has('requestPermission')){
      final answer=await (o.callMethod('requestPermission'.toJS) as JSPromise<JSString>).toDart;
      if(answer.toDart!='granted')return null;
    }
  }catch(_){return null;}
  late StreamController<double> out;
  JSFunction? handler;
  void listen(String type){
    handler=((web.Event e){
      final ev=e as JSObject;
      final ios=ev['webkitCompassHeading'];
      if(ios!=null&&ios.isA<JSNumber>()){out.add((ios as JSNumber).toDartDouble);return;}
      final alpha=ev['alpha'], absolute=ev['absolute'];
      if(alpha!=null&&alpha.isA<JSNumber>()&&(type=='deviceorientationabsolute'||(absolute!=null&&(absolute as JSBoolean).toDart))){
        out.add((360-(alpha as JSNumber).toDartDouble)%360);
      }
    }).toJS;
    web.window.addEventListener(type,handler);
  }
  final type=globalContext.has('ondeviceorientationabsolute')?'deviceorientationabsolute':'deviceorientation';
  out=StreamController<double>.broadcast(onListen:()=>listen(type),onCancel:(){if(handler!=null)web.window.removeEventListener(type,handler);});
  return out.stream;
}

/// Whether the browser gives a heading (asks the permission on iPhone).
Future<bool> hasCompass() async=>await compassHeadings()!=null;

/// Same compass as the installed apps (shared_compass.dart): the browser
/// heading once allowed; nothing on a computer.
Stream<CompassReading>? compassReadings(){
  late StreamController<CompassReading> out;
  StreamSubscription<double>? sub;
  out=StreamController<CompassReading>.broadcast(onListen:() async {
    final s=await compassHeadings();
    if(s==null){await out.close();return;}
    sub=s.listen((d)=>out.add(CompassReading(d)),onError:(_){});
  },onCancel:(){sub?.cancel();});
  return out.stream;
}

/// The browser does not give the local address (Paramètres › Diagnostic).
Future<List<String>> localAddresses() async=>const [];

/// Files dropped from the computer's file manager onto the browser window
/// (« Fichiers, glisser-déposer », 30 Oct 2026): HTML drag and drop, no
/// package. Each drop gives its files (name and content).
Stream<List<({String name,List<int> bytes})>> desktopFileDrops(){
  late final StreamController<List<({String name,List<int> bytes})>> c;
  bool hasFiles(web.DragEvent e){
    final types=e.dataTransfer?.types.toDart??const <JSString>[];
    return types.any((t)=>t.toDart=='Files');
  }
  final over=((web.DragEvent e){if(hasFiles(e)){e.preventDefault();e.dataTransfer?.dropEffect='copy';}}).toJS;
  Future<void> read(web.FileList list) async {
    final out=<({String name,List<int> bytes})>[];
    for(var i=0;i<list.length;i++){
      final f=list.item(i); if(f==null)continue;
      try{out.add((name:f.name,bytes:(await f.arrayBuffer().toDart).toDart.asUint8List()));}catch(_){}
    }
    if(out.isNotEmpty&&!c.isClosed)c.add(out);
  }
  final drop=((web.DragEvent e){
    final list=e.dataTransfer?.files; if(list==null||list.length==0)return;
    e.preventDefault();
    unawaited(read(list));
  }).toJS;
  c=StreamController<List<({String name,List<int> bytes})>>(
    onListen:(){web.window.addEventListener('dragover',over);web.window.addEventListener('drop',drop);},
    onCancel:(){web.window.removeEventListener('dragover',over);web.window.removeEventListener('drop',drop);});
  return c.stream;
}

// Startup log and smoke test: the browser console is enough on the web.
String? startupLogPath()=>null;
void writeStartupLog(String line){}
String? smokeReportPath()=>null;
void writeSmokeReport(String text){}
void exitProcess(int code){}
