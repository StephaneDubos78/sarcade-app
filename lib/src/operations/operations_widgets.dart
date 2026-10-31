import 'package:flutter/material.dart';
import '../config/version.dart';
import '../l10n/strings.dart';
import '../models/web_update.dart' show versionChange;
import '../platform/platform_services.dart';
import '../services/sarcade_api.dart';
import 'event_settings.dart';
import 'tracking_service.dart';

/// Banners above the map: event closed, minimal version, low-bandwidth mode,
/// items not sent for too long (notes « Synchronisation client-serveur » and
/// « Mises à jour et sécurité »).
class OperationsBanners extends StatelessWidget {
  final EventSettings settings; final ClientUpdate update;
  final ({int count,int minutes})? alert; final int heldPhotos;
  final VoidCallback onSyncNow; final VoidCallback onUpdate;
  /// Cloudflare Access: sign-in required, or session ending within 24 h.
  final bool accessRequired; final DateTime? accessRenewBy; final VoidCallback? onSignIn;
  /// Web client: the server stopped answering while the browser is online,
  /// usually an expired session; reloading the page signs in again.
  final VoidCallback? onReload;
  /// Web client: notifications not yet allowed; the browser only asks after
  /// a click, hence this banner.
  final VoidCallback? onEnableNotifications; final VoidCallback? onDismissNotifications;
  /// Web client: a newer build is served; reloading runs it.
  final VoidCallback? onWebUpdate;
  /// « (0.1.0+535 → 0.1.0+560) » and, in the tooltip, the commits.
  final String webUpdateChange, webUpdateBuilds;
  /// What is blocked (« 1 photo non envoyée », unsent_summary.dart) and the
  /// list of the items not sent, opened by a touch on the banner.
  final String? alertWhat; final VoidCallback? onOpenUnsent;
  const OperationsBanners({super.key,required this.settings,required this.update,required this.alert,
    required this.heldPhotos,required this.onSyncNow,required this.onUpdate,
    this.accessRequired=false,this.accessRenewBy,this.onSignIn,this.onReload,
    this.onEnableNotifications,this.onDismissNotifications,this.onWebUpdate,this.alertWhat,this.onOpenUnsent,this.webUpdateChange='',this.webUpdateBuilds=''});

  static String _date(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';}

  String _time(DateTime t){final l=t.toLocal();return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';}

  /// Something to show: the phone map then starts below the banners
  /// instead of under the status bar.
  bool get visible=>accessRequired||accessRenewBy!=null||onReload!=null||onWebUpdate!=null||onEnableNotifications!=null||
    settings.eventEnded||update.status==UpdateStatus.invited||update.status==UpdateStatus.deferred||settings.lowBandwidth||alert!=null;

  @override
  Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final rows=<Widget>[
      if(accessRequired)_Banner(icon:Icons.lock_outline,color:Colors.orange.shade200,
        text:S.t('access.required'),
        action:onSignIn==null?null:OutlinedButton(onPressed:onSignIn,child:Text(S.t('access.signIn')))),
      if(!accessRequired&&accessRenewBy!=null)_Banner(icon:Icons.lock_clock,color:Colors.amber.shade100,
        text:S.t('access.renew',{'date':_date(accessRenewBy!)}),
        action:onSignIn==null?null:OutlinedButton(onPressed:onSignIn,child:Text(S.t('access.signInAgain')))),
      if(onReload!=null)_Banner(icon:Icons.refresh,color:Colors.orange.shade100,
        text:S.t('access.webExpired'),
        action:OutlinedButton(onPressed:onReload,child:Text(S.t('access.reload')))),
      // Night blue, white text, lighter blue button (29 Oct 2026).
      if(onWebUpdate!=null)Tooltip(message:webUpdateBuilds,child:_Banner(key:const ValueKey('web-update-banner'),icon:Icons.system_update_alt,color:webUpdateBannerColor,foreground:Colors.white,
        text:'$webUpdateChange${S.t('webUpdate.available')}',
        action:FilledButton(onPressed:onWebUpdate,
          style:FilledButton.styleFrom(backgroundColor:webUpdateButtonColor,foregroundColor:Colors.white),
          child:Text(S.t('webUpdate.reload'))))),
      if(onEnableNotifications!=null)_Banner(icon:Icons.notifications_active_outlined,color:scheme.secondaryContainer,
        text:S.t('notifications.prompt'),
        action:Row(mainAxisSize:MainAxisSize.min,children:[
          if(onDismissNotifications!=null)OutlinedButton(onPressed:onDismissNotifications,child:Text(S.t('notifications.later'))),
          OutlinedButton(onPressed:onEnableNotifications,child:Text(S.t('notifications.enable'))),
        ])),
      if(settings.eventEnded)_Banner(icon:Icons.flag,color:scheme.tertiaryContainer,
        text:'${S.t('event.ended')} · ${S.t('event.endedDetail')}'),
      if(update.status==UpdateStatus.invited)_Banner(icon:Icons.system_update,color:scheme.secondaryContainer,
        text:'${versionChange(appVersionFull,update.targetVersion)}${S.t('update.invited',{'version':update.targetVersion,'deadline':update.deadline==null?'-':_time(update.deadline!)})}',
        action:update.packageUrl==null?null:OutlinedButton(onPressed:onUpdate,child:Text(S.t('update.download')))),
      if(update.status==UpdateStatus.deferred)_Banner(icon:Icons.system_update,color:scheme.secondaryContainer,
        text:S.t('update.deferred',{'version':update.targetVersion})),
      if(settings.lowBandwidth)_Banner(icon:Icons.network_check,color:Colors.amber.shade200,
        text:S.t('lowband.on',{'s':settings.lowBandwidthIntervalS})+(heldPhotos>0?' · ${S.t('lowband.photosHeld',{'n':heldPhotos})}':'')),
      if(alert!=null)_Banner(key:const ValueKey('unsent-banner'),icon:Icons.sync_problem,color:scheme.errorContainer,onTap:onOpenUnsent,
        text:(alertWhat??'').isEmpty?S.t('sync.alert',{'n':alert!.count,'min':alert!.minutes}):S.t('unsent.since2',{'what':alertWhat,'min':alert!.minutes}),
        action:OutlinedButton(onPressed:onSyncNow,child:Text(S.t('sync.now')))),
    ];
    if(rows.isEmpty)return const SizedBox.shrink();
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:rows);
  }
}

const webUpdateBannerColor=Color(0xFF14213D), webUpdateButtonColor=Color(0xFF3D7BFF);

class _Banner extends StatelessWidget {
  final IconData icon; final Color color; final String text; final Widget? action; final Color? foreground; final VoidCallback? onTap;
  const _Banner({super.key,required this.icon,required this.color,required this.text,this.action,this.foreground,this.onTap});
  @override Widget build(BuildContext context)=>Material(color:color,child:InkWell(onTap:onTap,child:Padding(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
    child:Row(children:[Icon(icon,size:18,color:foreground),const SizedBox(width:8),
      Expanded(child:Text(text,style:Theme.of(context).textTheme.bodySmall?.copyWith(color:foreground))),
      if(onTap!=null)Icon(Icons.chevron_right,size:18,color:foreground),?action]),
  )));
}

/// Screen shown when the server refuses this version (2 hours after the
/// invitation, outside an active event).
class UpdateRequiredPage extends StatefulWidget {
  final SarcadeApi api; final ClientUpdate update; final String platform;
  const UpdateRequiredPage({super.key,required this.api,required this.update,required this.platform});
  @override State<UpdateRequiredPage> createState()=>_UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(S.t('update.required')),automaticallyImplyLeading:false),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.system_update,size:56),
      const SizedBox(height:16),
      Text(S.t('update.requiredDetail',{'current':appVersion,'version':widget.update.targetVersion}),textAlign:TextAlign.center),
      const SizedBox(height:20),
      if(widget.update.packageUrl!=null)FilledButton.icon(onPressed:()=>downloadUpdate(context,widget.api,widget.update),icon:const Icon(Icons.download),label:Text(S.t('update.download')))
      else Text(S.t('update.store'),textAlign:TextAlign.center),
    ])))),
  );
}

/// Downloads the client package offered by the local server and opens it
/// (installer on Windows, APK on Android, AppImage on Linux). The system
/// checks the platform signature before installing.
Future<void> downloadUpdate(BuildContext context,SarcadeApi api,ClientUpdate update) async {
  final messenger=ScaffoldMessenger.of(context);
  final url=update.packageUrl;
  if(url==null)return;
  try{
    final bytes=await api.download(url);
    final name=url.split('/').where((p)=>p.isNotEmpty).toList().reversed.skip(1).firstOrNull??'client';
    final path=await saveFile('sarcade-${update.targetVersion}-$name${_extension(name)}',bytes,mimeType:'application/octet-stream');
    messenger.showSnackBar(SnackBar(content:Text(S.t('update.downloaded')),
      action:!canOpenSavedFiles?null:SnackBarAction(label:S.t('common.ok'),onPressed:()=>openSavedFile(path))));
  }catch(_){
    messenger.showSnackBar(SnackBar(content:Text(S.t('update.downloadFailed'))));
  }
}

String _extension(String platform)=>switch(platform){'windows'=>'.exe','appimage'=>'.AppImage','apk'=>'.apk',_=>''};

/// Sheet to start or stop the Beacon and choose its interval.
Future<void> showTrackingSheet(BuildContext context,{required TrackingService tracking,required EventSettings settings,
    required Future<void> Function(bool enabled,int intervalS) onChange}) {
  return showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(context)=>StatefulBuilder(builder:(context,setSheet){
    final allowed=settings.allowedIntervals;
    final current=settings.clampInterval(tracking.intervalS);
    return SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,0,20,20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(S.t('tracking.title'),style:Theme.of(context).textTheme.titleLarge),
      if(settings.trackingRequired)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('tracking.requiredLocked'))),
      const SizedBox(height:12),
      Text(S.t('tracking.interval',{'interval':intervalLabel(current,S.t)})),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[for(final s in allowed)ChoiceChip(
        label:Text(intervalLabel(s,S.t)),selected:s==current,
        onSelected:(_) async {await onChange(tracking.enabled,s);setSheet((){});},
      )]),
      const SizedBox(height:16),
      SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:settings.trackingRequired&&tracking.enabled?null:() async {await onChange(!tracking.enabled,current);if(context.mounted)Navigator.pop(context);},
        icon:Icon(tracking.enabled?Icons.location_off:Icons.my_location),
        label:Text(tracking.enabled?S.t('tracking.stop'):S.t('tracking.start')),
      )),
    ])));
  }));
}
