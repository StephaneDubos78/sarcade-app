import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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
