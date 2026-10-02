import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/offline/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store=LocalStore();
  await store.init();
  runApp(SarcadeApp(store:store));
}
