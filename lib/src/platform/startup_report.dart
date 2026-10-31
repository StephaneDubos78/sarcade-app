/// Startup report (card « Client Windows : écran gris au démarrage », 31 Oct
/// 2026). In a release build Flutter replaces a widget that fails by a grey
/// box, and an error before the first screen leaves the window empty: on
/// Windows there is no console, so nothing told what broke. Now:
/// - every error is written to the startup log (platform_services:
///   %LOCALAPPDATA%\SARCADE\logs\demarrage.log on Windows) and printed;
/// - a widget that fails shows a readable message instead of grey;
/// - an error before the first screen shows a full error screen, with the
///   message, the log file and « Copier ».
/// With SARCADE_SMOKE_FILE set (CI), a report is written once the first
/// screen is up, then the process ends: 0 without error, 1 otherwise.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../config/version.dart';
import 'platform_services.dart';

class StartupReport {
  StartupReport._();
  static final errors=<String>[];
  static bool firstFrame=false;

  static void begin(){
    writeStartupLog('--- SARCADE $appVersionFull ${appBuild.isEmpty?'':appBuild} '
      '(${kIsWeb?'web':defaultTargetPlatform.name}, ${kReleaseMode?'release':'debug'})');
  }

  static void note(String line){writeStartupLog(line);debugPrint('SARCADE: $line');}

  /// Records an error: log file, console, smoke report.
  static void error(String where,Object error,StackTrace? stack){
    final text='$where: $error';
    errors.add(text);
    writeStartupLog('ERREUR $text\n${stack??''}');
    debugPrint('SARCADE error: $text\n${stack??''}');
  }

  /// Smoke test of the CI: once the first frame is drawn, waits a few
  /// seconds (late errors of the first screen), writes the report, quits.
  static void watchFirstFrame(){
    SchedulerBinding.instance.addPostFrameCallback((_){
      firstFrame=true;
      note('premier écran affiché');
      if(smokeReportPath()==null)return;
      Timer(const Duration(seconds:8),(){
        writeSmokeReport(smokeJson());
        exitProcess(errors.isEmpty?0:1);
      });
    });
  }

  static String smokeJson()=>const JsonEncoder.withIndent('  ').convert({
    'version':appVersionFull,'build':appBuild,'first_frame':firstFrame,'errors':errors,'log':startupLogPath(),
  });
}

/// Replaces the grey box of a failing widget (release builds).
Widget readableErrorWidget(FlutterErrorDetails d){
  final log=startupLogPath();
  return Directionality(textDirection:TextDirection.ltr,child:Container(
    color:const Color(0xFFFFF3E0),padding:const EdgeInsets.all(12),alignment:Alignment.topLeft,
    child:SingleChildScrollView(child:Text(
      'Erreur d’affichage / Display error\n${d.exceptionAsString()}${log==null?'':'\n\nJournal / Log: $log'}',
      style:const TextStyle(color:Color(0xFF6D2B00),fontSize:13,decoration:TextDecoration.none)))));
}

/// Full screen when the app cannot start (error before the first screen).
class StartupErrorApp extends StatelessWidget {
  final String message;
  const StartupErrorApp({super.key,required this.message});
  @override Widget build(BuildContext context){
    final log=startupLogPath();
    final details='$message${log==null?'':'\n\nJournal / Log: $log'}\nSARCADE $appVersionFull $appBuild';
    return MaterialApp(title:'SARCADE',debugShowCheckedModeBanner:false,home:Scaffold(body:SafeArea(child:Padding(
      padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Icon(Icons.error_outline,size:48,color:Colors.red),
        const SizedBox(height:12),
        const Text('SARCADE n’a pas pu démarrer',style:TextStyle(fontSize:22,fontWeight:FontWeight.w600)),
        const Text('SARCADE could not start'),
        const SizedBox(height:16),
        Expanded(child:SingleChildScrollView(child:SelectableText(details,style:const TextStyle(fontFamily:'monospace',fontSize:13)))),
        const SizedBox(height:12),
        Builder(builder:(context)=>FilledButton.icon(icon:const Icon(Icons.copy),label:const Text('Copier / Copy'),
          onPressed:()async{await Clipboard.setData(ClipboardData(text:details));
            if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Copié / Copied')));})),
      ])))));
  }
}
