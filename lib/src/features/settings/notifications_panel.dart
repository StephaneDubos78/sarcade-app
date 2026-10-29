import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../../offline/local_store.dart';
import '../../operations/event_settings.dart' show StoreRelease;
import '../../operations/version_state.dart';
import '../../platform/platform_services.dart';
import '../../services/notification_service.dart';
import '../../services/notification_actions.dart' show soundChoices, soundDefaults;
import '../../services/sarcade_api.dart';
import '../../services/wakeup_fcm.dart';
import '../../services/wakeup_state.dart';

/// Sound by priority kept on the device (« notif_sound:routine » …).
Map<String,String> readSoundPrefs(LocalStore? store)=>{
  for(final p in soundChoices.keys)
    if(store?.preference('notif_sound:$p') case final String v)p:v};

bool get _android=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
bool get _ios=>!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS;
/// Wake-up when SARCADE is closed exists here: Web Push or Firebase.
bool get wakeupSupported=>isWebPlatform||fcmAvailable;

/// Rows of Paramètres › Notifications (decisions of 29 Oct 2026): state of
/// the permissions, « Tester le réveil » with its result, sound by priority.
class NotificationsPanel extends StatefulWidget {
  final SarcadeApi? api; final String eventId, deviceId; final LocalStore? store;
  /// One row of the settings screen (label, help, control).
  final Widget Function(String label,{String? help,required Widget child}) row;
  const NotificationsPanel({super.key,required this.api,required this.eventId,required this.deviceId,required this.store,required this.row});
  @override State<NotificationsPanel> createState()=>_NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> with WidgetsBindingObserver {
  bool? _allowed; bool _testing=false; String? _result; bool _received=false;
  late Map<String,String> _sounds=readSoundPrefs(widget.store);

  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_read();}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  // Back from the system settings: read the permission again.
  @override void didChangeAppLifecycleState(AppLifecycleState s){if(s==AppLifecycleState.resumed)_read();}

  Future<void> _read() async {
    final v=await NotificationService().permissionGranted();
    if(mounted)setState(()=>_allowed=v);
  }

  Future<void> _fixPermission() async {
    await NotificationService().openPermissionSettings();
    await _read();
    if(_allowed==true)wakeupRegistered.value=await registerWakeupHook?.call()??wakeupRegistered.value;
  }

  Future<void> _test() async {
    final api=widget.api;
    if(api==null)return;
    setState((){_testing=true;_result=null;});
    final got=Completer<bool>();
    final sub=(isWebPlatform?webWakeSignals():fcmForeground()).listen((d){if(d['kind']=='test'&&!got.isCompleted)got.complete(true);});
    var ok=false;
    try{
      final hook=registerWakeupHook;
      if(hook!=null)wakeupRegistered.value=await hook();
      final r=await api.testWakeup(widget.eventId,widget.deviceId);
      if(((r['sent'] as num?)??0)>0)ok=await got.future.timeout(const Duration(seconds:20),onTimeout:()=>false);
    }catch(_){ok=false;}
    await sub.cancel();
    await _read();
    if(mounted)setState((){_testing=false;_received=ok;_result=ok?S.t('wakeup.received'):S.t('wakeup.notReceived');});
  }

  Future<void> _setSound(String priority,String v) async {
    setState(()=>_sounds={..._sounds,priority:v});
    NotificationService().sounds=_sounds;
    await widget.store?.setPreference('notif_sound:$priority',v);
  }

  Widget _state(bool? on,String yes,String no){
    final t=Theme.of(context);
    final colour=on==true?Colors.green.shade700:on==false?t.colorScheme.error:t.colorScheme.onSurfaceVariant;
    return Row(mainAxisSize:MainAxisSize.min,children:[
      Icon(on==true?Icons.check_circle:on==false?Icons.error_outline:Icons.help_outline,size:18,color:colour),
      const SizedBox(width:6),Flexible(child:Text(on==null?S.t('settings.unknown'):on?yes:no,style:TextStyle(color:colour))),
    ]);
  }

  Widget _segments(String priority)=>Align(alignment:Alignment.centerLeft,child:SegmentedButton<String>(
    showSelectedIcon:false,
    segments:[for(final c in soundChoices[priority]!)ButtonSegment(value:c,label:Text(S.t('sound.$c')))],
    selected:{_sounds[priority]??soundDefaults[priority]!},
    onSelectionChanged:(v)=>unawaited(_setSound(priority,v.first)),
  ));

  @override
  Widget build(BuildContext context){
    final row=widget.row;
    final blocked=NotificationService().permissionBlocked;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      row(S.t('settings.notifAllowed'),help:blocked?S.t('notifications.refused'):null,child:Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
        _state(_allowed,S.t('settings.allowed'),S.t('settings.notAllowed')),
        if(_allowed==false&&!blocked)FilledButton.tonal(onPressed:_fixPermission,
          child:Text(isWebPlatform?S.t('notifications.enable'):S.t('settings.openSystem'))),
      ])),
      if(wakeupSupported)row(S.t('settings.wakeupClosed'),help:S.t(isWebPlatform?'settings.wakeupWeb':'settings.wakeupFcm'),
        child:ValueListenableBuilder<bool?>(valueListenable:wakeupRegistered,builder:(_,on,_)=>Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
          _state(on,S.t('settings.active'),S.t('settings.inactive')),
          if(on==false&&!blocked)FilledButton.tonal(onPressed:_fixPermission,
            child:Text(isWebPlatform?S.t('notifications.enable'):S.t('settings.openSystem'))),
        ]))),
      if(wakeupSupported&&widget.api!=null)row(S.t('wakeup.test'),help:S.t('wakeup.testSettingsHelp'),child:Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
        FilledButton.tonalIcon(onPressed:_testing?null:_test,
          icon:_testing?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.notifications_active_outlined),
          label:Text(S.t('wakeup.test'))),
        if(_result!=null)Text(_result!,style:TextStyle(fontWeight:FontWeight.w600,
          color:_received?Colors.green.shade700:Theme.of(context).colorScheme.error)),
      ])),
      row(S.t('sound.routine'),help:S.t('sound.routineHelp'),child:_segments('routine')),
      row(S.t('sound.urgent'),child:_segments('urgent')),
      row(S.t('sound.immediate'),help:S.t('sound.sosHelp'),child:_segments('immediate')),
      if(_ios)row(S.t('settings.dndBypass'),help:S.t('settings.criticalIos'),child:const SizedBox.shrink()),
    ]);
  }
}

/// Phones: « À jour » or « Nouvelle version disponible » with « Mettre à
/// jour » (TestFlight, Google Play); never an obligation (29 Oct 2026).
class VersionStatus extends StatelessWidget {
  const VersionStatus({super.key});
  static bool get shown=>_android||_ios;

  static Future<void> openStore(StoreRelease release) async {
    final urls=[
      if(release.url!=null)release.url!,
      if(_ios)...['itms-beta://','https://testflight.apple.com/'],
      if(_android)...['market://details?id=$androidApplicationId','https://play.google.com/store/apps/details?id=$androidApplicationId'],
    ];
    for(final u in urls){
      try{if(await launchUrl(Uri.parse(u),mode:LaunchMode.externalApplication))return;}catch(_){/* next one */}
    }
  }

  @override
  Widget build(BuildContext context)=>!shown?const SizedBox.shrink():ValueListenableBuilder<StoreRelease?>(valueListenable:latestRelease,builder:(context,r,_){
    if(r==null)return const SizedBox.shrink();
    final t=Theme.of(context);
    if(!r.newerThan(appVersion,appBuildNumber)){
      return Row(children:[Icon(Icons.check_circle,size:18,color:Colors.green.shade700),const SizedBox(width:6),Text(S.t('version.upToDate'))]);
    }
    return Wrap(spacing:12,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
      Text(r.build==null?S.t('version.available',{'version':r.version}):S.t('version.availableBuild',{'version':r.version,'build':r.build}),
        style:TextStyle(color:t.colorScheme.primary,fontWeight:FontWeight.w600)),
      FilledButton.icon(onPressed:()=>unawaited(openStore(r)),icon:const Icon(Icons.system_update),label:Text(S.t('version.update'))),
    ]);
  });
}

/// Application identifier on Google Play (AGENTS.md).
const androidApplicationId='org.sarcade.sarcade_app';
