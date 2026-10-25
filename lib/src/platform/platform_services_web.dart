import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

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
Future<String?> fetchServedBuild() async {
  try{
    final url='sarcade_build.json?t=${DateTime.now().millisecondsSinceEpoch}';
    final r=await web.window.fetch(url.toJS,web.RequestInit(cache:'no-store',credentials:'include')).toDart;
    if(!r.ok)return null;
    final text=(await r.text().toDart).toDart;
    return parseServedBuild(jsonDecode(text));
  }catch(_){return null;}
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
  web.window.location.reload();
}
bool get browserOnline=>web.window.navigator.onLine;

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
