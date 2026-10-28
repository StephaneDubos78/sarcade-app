import 'package:flutter/material.dart';
import 'src/access/access_manager.dart';
import 'src/app.dart';
import 'src/offline/local_store.dart';
import 'src/platform/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds hide widget errors (blank area): print them in the
  // console too, so a field report or the browser console tells what broke.
  final previous=FlutterError.onError;
  FlutterError.onError=(details){
    debugPrint('SARCADE error: ${details.exceptionAsString()}\n${details.stack}');
    previous?.call(details);
  };
  if (!await acquireSingleInstance()) {
    // Windows V0.1: refuse a second process before Hive is opened.
    // Native foreground activation will be added in the packaged Windows runner.
    quitApp();
    return;
  }
  final store=LocalStore();
  await store.init();
  await AccessManager.instance.load();
  runApp(SarcadeApp(store:store));
}
