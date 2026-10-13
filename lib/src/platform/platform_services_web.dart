import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:web/web.dart' as web;

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
