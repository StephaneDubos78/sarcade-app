import 'dart:async';
import 'ui/overlay_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'config/app_config.dart';
import 'config/saved_servers.dart';
import 'ui/theme.dart';
import 'features/map/operational_map_page.dart';
import 'features/settings/settings_page.dart';
import 'features/logbook/logbook_page.dart';
import 'services/sarcade_api.dart';
import 'offline/local_store.dart';
import 'offline/outbox_policy.dart' as outbox;
import 'offline/sync_service.dart';
import 'l10n/strings.dart';
import 'operations/event_settings.dart';
import 'services/notification_service.dart';
import 'features/settings/notifications_panel.dart' show readSoundPrefs;

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
    _applyLanguage();
    themeMode.value=themeModeFrom(widget.store.preference('theme_mode'));
  }

  void _applyLanguage(){
    S.setLanguage(_config.language,systemLanguage:WidgetsBinding.instance.platformDispatcher.locale.languageCode);
    NotificationService().bypassDnd=_config.immediateBypassDnd;
    NotificationService().sounds=readSoundPrefs(widget.store);
  }

  static String get _platform=>platformName(isWeb:kIsWeb,targetPlatform:defaultTargetPlatform.name);

  List<SavedServer> _readServers()=>parseSavedServers(widget.store.preference('servers'));
  Future<void> _saveServers(List<SavedServer> list)=>widget.store.setPreference('servers',encodeSavedServers(list));
  Future<void> _rememberServer(String url,{String? eventId,String? deviceId})=>
    _saveServers(rememberServer(_readServers(),url,eventId:eventId,deviceId:deviceId,now:DateTime.now().toUtc()));

  Future<void> _save(AppConfig c) async {
    final colourChanged=c.drawColor!=null&&c.drawColor!=_config.drawColor;
    await widget.store.saveConfig(c.toStored());
    // Preferred colour kept by the server for the email (every device and
    // event); refused silently without Cloudflare Access.
    if(colourChanged)unawaited(_apiFor(c).patchMyPreferences({'color':c.drawColor}).catchError((_)=>false));
    // Last event and terminal of this server, taken back when switching to it.
    await _rememberServer(c.serverUrl,eventId:c.eventId,deviceId:c.deviceId);
    final wasSetup=_needsSetup;
    // Same session: language or operator settings changed, the map stays.
    if(c.sessionKey==_config.sessionKey&&!wasSetup){setState((){_config=c;_applyLanguage();});_navigator.currentState?.maybePop();return;}
    setState((){_config=c;_needsSetup=false;_applyLanguage();});
    if(!wasSetup)_navigator.currentState?.maybePop();
  }

  final _httpsTried=<String>{};

  /// Switch to the HTTPS address announced by the server, kept when it
  /// answers (certificate valid, local DNS in place); otherwise the device
  /// stays on plain HTTP and tries again at the next start.
  Future<void> _tryHttps(String url) async {
    if(!_httpsTried.add(url))return;
    try{
      final r=await http.get(Uri.parse('$url/health')).timeout(const Duration(seconds:8));
      if(r.statusCode!=200||!mounted)return;
      final c=_config.copyWith(serverUrl:url);
      await widget.store.saveConfig(c.toStored());
      setState(()=>_config=c);
    }catch(e){
      debugPrint('SARCADE HTTPS address not reachable yet ($url): $e');
    }
  }


  void _openSettings()=>_navigator.currentState?.push(MaterialPageRoute(builder:(_)=>_settingsPage(firstRun:false)));

  SettingsPage _settingsPage({required bool firstRun})=>SettingsPage(
    initial:_config,onSave:_save,firstRun:firstRun,
    loadEvents:_loadEvents,cachedEvents:widget.store.cachedEvents,
    waitingFor:(server,eventId)=>outbox.waitingFor(widget.store.pending(),server,eventId),
    sendFirst:_sendFirst,
    readServers:_readServers,saveServers:_saveServers,
    api:firstRun?null:_apiFor(_config),store:widget.store,
    onThemeChanged:(m)=>widget.store.setPreference('theme_mode',themeModeName(m)),
    onOpenLogbook:firstRun?null:(){
      // A window over Paramètres (« façon Google Play Console », 30 Oct 2026).
      final c=_navigator.currentState?.overlay?.context;
      if(c!=null)showOverlayPage<void>(c,(_)=>LogbookPage(api:_apiFor(_config),eventId:_config.eventId));
    },
  );

  Future<List<Map<String,dynamic>>> _loadEvents(String server) async {
    final api=SarcadeApi(baseUrl:server);
    try{
      final list=await api.events();
      await widget.store.saveEvents(server,list);
      // First successful connection: the server is remembered.
      await _rememberServer(server);
      return list;
    }finally{api.close();}
  }

  /// « Envoyer d'abord »: the open map's sender when it is the same server
  /// and event, otherwise a one-shot one. Returns what is still waiting.
  Future<int> _sendFirst(String server,String eventId) async {
    final live=OfflineSyncService.active;
    if(live!=null&&outbox.normalServer(live.server)==outbox.normalServer(server)&&live.eventId==eventId){
      await live.syncNow();
    }else{
      final api=SarcadeApi(baseUrl:server);
      final once=OfflineSyncService(api:api,store:widget.store,eventId:eventId);
      try{await once.syncNow();}finally{api.close();}
    }
    return outbox.waitingFor(widget.store.pending(),server,eventId);
  }

  @override
  Widget build(BuildContext context)=>ValueListenableBuilder<ThemeMode>(valueListenable:themeMode,builder:(context,mode,_)=>MaterialApp(
    navigatorKey:_navigator,
    title:'SARCADE',
    debugShowCheckedModeBanner:false,
    // Labels of the standard widgets read by screen readers in the language
    // of SARCADE (revue d'ergonomie n° 70: « Show menu », « Dismiss »).
    locale:Locale(S.lang),supportedLocales:const [Locale('fr'),Locale('en')],
    localizationsDelegates:GlobalMaterialLocalizations.delegates,
    theme:dayTheme(),darkTheme:nightTheme(),themeMode:mode,
    home:_needsSetup
      ? _settingsPage(firstRun:true)
      : OperationalMapPage(
          key:ValueKey(_config.sessionKey),
          api:_apiFor(_config),
          eventId:_config.eventId,deviceId:_config.deviceId,store:widget.store,
          tileUrl:_config.tileUrl,tileAttribution:_config.tileAttribution,
          onSettings:_openSettings,
          settingsBuilder:()=>_settingsPage(firstRun:false),
          callsign:_config.callsign,aprsTxConsent:_config.aprsTxConsent,platform:_platform,
          onHttpsAvailable:_tryHttps,
        ),
  ));
}
