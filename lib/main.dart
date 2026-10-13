import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/offline/local_store.dart';
import 'src/platform/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!await acquireSingleInstance()) {
    // Windows V0.1: refuse a second process before Hive is opened.
    // Native foreground activation will be added in the packaged Windows runner.
    quitApp();
    return;
  }
  final store=LocalStore();
  await store.init();
  runApp(SarcadeApp(store:store));
}
