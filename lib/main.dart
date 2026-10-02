import 'dart:io';
import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/offline/local_store.dart';

RandomAccessFile? _instanceLock;

Future<bool> _acquireSingleInstance() async {
  if (!Platform.isWindows) return true;
  final base=Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  final dir=Directory('$base\\SARCADE');
  await dir.create(recursive:true);
  final file=File('${dir.path}\\sarcade-client.lock');
  final handle=await file.open(mode:FileMode.write);
  try {
    await handle.lock(FileLock.exclusive);
    _instanceLock=handle;
    return true;
  } on FileSystemException {
    await handle.close();
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!await _acquireSingleInstance()) {
    // V0.1: refuse a second process before Hive is opened.
    // Native foreground activation will be added in the packaged Windows runner.
    exit(0);
  }
  final store=LocalStore();
  await store.init();
  runApp(SarcadeApp(store:store));
}
