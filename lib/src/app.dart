import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'features/map/operational_map_page.dart';
import 'features/settings/settings_page.dart';
import 'services/sarcade_api.dart';
import 'offline/local_store.dart';

class SarcadeApp extends StatefulWidget {
  final LocalStore store;
  const SarcadeApp({super.key,required this.store});
  @override State<SarcadeApp> createState()=>_SarcadeAppState();
}

class _SarcadeAppState extends State<SarcadeApp> {
  final _navigator=GlobalKey<NavigatorState>();
  late AppConfig _config;
  late bool _needsSetup;
  SarcadeApi? _api;
  String? _apiKey;

  // One client per session: the map page closes it on dispose.
  SarcadeApi _apiFor(AppConfig c){if(_apiKey!=c.sessionKey){_api=SarcadeApi(baseUrl:c.serverUrl);_apiKey=c.sessionKey;}return _api!;}

  // Phones and the web app (Chromebooks, PWA) cannot receive --dart-define
  // values per operator, so they ask the settings once.
  static bool get _asksSettings=>kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS;

  @override void initState(){
    super.initState();
    final env=AppConfig.fromEnvironment();
    final stored=widget.store.storedConfig();
    _config=stored==null?env:AppConfig.fromStored(stored,env);
    // Desktop keeps the build-time configuration (run-windows-demo.ps1).
    // A phone cannot be given --dart-define values per operator, so it asks once.
    _needsSetup=!_config.isComplete||(_asksSettings&&stored==null);
  }

  Future<void> _save(AppConfig c) async {
    await widget.store.saveConfig(c.toStored());
    final wasSetup=_needsSetup;
    if(c.sessionKey==_config.sessionKey&&!wasSetup){_navigator.currentState?.pop();return;}
    setState((){_config=c;_needsSetup=false;});
    if(!wasSetup)_navigator.currentState?.pop();
  }

  void _openSettings()=>_navigator.currentState?.push(MaterialPageRoute(builder:(_)=>SettingsPage(initial:_config,onSave:_save)));

  @override
  Widget build(BuildContext context)=>MaterialApp(
    navigatorKey:_navigator,
    title:'SARCADE',
    debugShowCheckedModeBanner:false,
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF173A6A)),useMaterial3:true),
    home:_needsSetup
      ? SettingsPage(initial:_config,onSave:_save,firstRun:true)
      : OperationalMapPage(
          key:ValueKey(_config.sessionKey),
          api:_apiFor(_config),
          eventId:_config.eventId,deviceId:_config.deviceId,store:widget.store,
          tileUrl:_config.tileUrl,tileAttribution:_config.tileAttribution,
          onSettings:_openSettings,
        ),
  );
}
