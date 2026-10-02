import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'features/map/operational_map_page.dart';
import 'services/sarcade_api.dart';
class SarcadeApp extends StatelessWidget {
 const SarcadeApp({super.key});
 @override Widget build(BuildContext context){final c=AppConfig.fromEnvironment();return MaterialApp(title:'SARCADE',debugShowCheckedModeBanner:false,theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF173A6A)),useMaterial3:true),home:OperationalMapPage(api:SarcadeApi(baseUrl:c.serverUrl),eventId:c.eventId,deviceId:c.deviceId));}
}
