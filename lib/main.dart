import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'src/app.dart';
import 'src/offline/local_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'sarcade-client',
      onSecondWindow: (args) {
        // The package restores/brings the existing SARCADE window to front.
        debugPrint('Second SARCADE launch intercepted: $args');
      },
    );
  }

  final store=LocalStore();
  await store.init();
  runApp(SarcadeApp(store:store));
}
