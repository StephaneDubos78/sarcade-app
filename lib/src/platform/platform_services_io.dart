import 'dart:io';
import 'package:sarcade_compass/sarcade_compass.dart';
import '../features/compass/compass_reading.dart';

import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Browser builds return true here; installed apps return false.
const isWebPlatform=false;

// Keep the file handle alive for the process lifetime so the exclusive lock remains held.
final _instanceLocks=<RandomAccessFile>[];

/// Windows V0.1 runs a single client: a second process is refused before
/// Hive is opened. Other platforms manage app instances themselves.
Future<bool> acquireSingleInstance() async {
  if(!Platform.isWindows)return true;
  final base=Platform.environment['LOCALAPPDATA']??Directory.systemTemp.path;
  final dir=Directory('$base\\SARCADE');
  await dir.create(recursive:true);
  final file=File('${dir.path}\\sarcade-client.lock');
  final handle=await file.open(mode:FileMode.write);
  try{
    await handle.lock(FileLock.exclusive);
    _instanceLocks.add(handle);
    return true;
  }on FileSystemException{
    await handle.close();
    return false;
  }
}

/// Ends the process, used when a second Windows instance is refused.
void quitApp()=>exit(0);

/// Windows keeps data under %LOCALAPPDATA%\SARCADE\data, outside OneDrive.
Future<void> initHiveStorage() async {
  if(Platform.isWindows){
    final base=Platform.environment['LOCALAPPDATA']??Directory.systemTemp.path;
    final dir=Directory('$base\\SARCADE\\data');
    await dir.create(recursive:true);
    Hive.init(dir.path);
  }else{
    await Hive.initFlutter('sarcade');
  }
}

/// Content of a file chosen with the file picker.
Future<List<int>?> readPickedFile(PlatformFile f) async=>f.bytes??(f.path==null?null:await File(f.path!).readAsBytes());

String _safeName(String name)=>name.replaceAll(RegExp(r'[\\/:*?"<>|]'),'_');

/// Saves bytes on the device and returns the path. [temporary] files go to
/// the cache (opened files), others to the documents folder (exports).
Future<String> saveFile(String name,List<int> bytes,{bool temporary=false,String? mimeType}) async {
  final dir=temporary?await getTemporaryDirectory():await getApplicationDocumentsDirectory();
  final path='${dir.path}${Platform.pathSeparator}${_safeName(name)}';
  await File(path).writeAsBytes(bytes,flush:true);
  return path;
}

/// Opens a saved file with the system application for its type.
Future<void> openSavedFile(String path) async {await OpenFilex.open(path);}

/// Whether saved files can be reopened from the app (false in a browser,
/// where a saved file is a download).
const canOpenSavedFiles=true;

/// Address of the server that served the app, only meaningful in a browser.
String? servingOrigin()=>null;

/// WebSocket with headers (Cloudflare Access session of the server).
WebSocketChannel openWebSocket(Uri uri,Map<String,String> headers)=>
  headers.isEmpty?WebSocketChannel.connect(uri):IOWebSocketChannel.connect(uri,headers:headers);

/// Installed apps: no page to reload; the network state is unknown here.
void reloadApp(){}

/// Installed apps are updated by their package: no served web build.
Future<String?> fetchServedBuild() async=>null;
Future<void> reloadFresh() async {}
Future<String?> webPushSubscription(String publicKey) async=>null;
/// Installed apps: the wake-up signals come by Firebase (wakeup_fcm.dart).
Stream<Map<String,dynamic>> webWakeSignals()=>const Stream<Map<String,dynamic>>.empty();
bool get browserOnline=>false;

/// Installed apps keep their data in their own folder.
Future<bool> requestPersistentStorage() async=>true;


/// Compass given by the system (Android rotation vector, iPhone Core
/// Location heading), magnetic north; null without compass (computers).
/// Whether this device has a compass (phones and tablets).
Future<bool> hasCompass() async=>Platform.isAndroid||Platform.isIOS;
Stream<CompassReading>? compassReadings(){
  if(!(Platform.isAndroid||Platform.isIOS))return null;
  return systemCompassEvents().map((e)=>CompassReading(e[0]<0?null:e[0],accuracyDeg:e.length>1&&e[1]>=0?e[1]:null,status:e.length>2?e[2].round():-1));
}
