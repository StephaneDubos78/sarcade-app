import 'package:flutter/material.dart';
import '../config/version.dart';
import '../l10n/strings.dart';
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
  const OperationsBanners({super.key,required this.settings,required this.update,required this.alert,
    required this.heldPhotos,required this.onSyncNow,required this.onUpdate});

  String _time(DateTime t){final l=t.toLocal();return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';}

  @override
  Widget build(BuildContext context){
    final scheme=Theme.of(context).colorScheme;
    final rows=<Widget>[
      if(settings.eventEnded)_Banner(icon:Icons.flag,color:scheme.tertiaryContainer,
        text:'${S.t('event.ended')} · ${S.t('event.endedDetail')}'),
      if(update.status==UpdateStatus.invited)_Banner(icon:Icons.system_update,color:scheme.secondaryContainer,
        text:S.t('update.invited',{'version':update.targetVersion,'deadline':update.deadline==null?'-':_time(update.deadline!)}),
        action:update.packageUrl==null?null:TextButton(onPressed:onUpdate,child:Text(S.t('update.download')))),
      if(update.status==UpdateStatus.deferred)_Banner(icon:Icons.system_update,color:scheme.secondaryContainer,
        text:S.t('update.deferred',{'version':update.targetVersion})),
      if(settings.lowBandwidth)_Banner(icon:Icons.network_check,color:Colors.amber.shade200,
        text:S.t('lowband.on',{'s':settings.lowBandwidthIntervalS})+(heldPhotos>0?' · ${S.t('lowband.photosHeld',{'n':heldPhotos})}':'')),
      if(alert!=null)_Banner(icon:Icons.sync_problem,color:scheme.errorContainer,
        text:S.t('sync.alert',{'n':alert!.count,'min':alert!.minutes}),
        action:TextButton(onPressed:onSyncNow,child:Text(S.t('sync.now')))),
    ];
    if(rows.isEmpty)return const SizedBox.shrink();
    return Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:rows);
  }
}

class _Banner extends StatelessWidget {
  final IconData icon; final Color color; final String text; final Widget? action;
  const _Banner({required this.icon,required this.color,required this.text,this.action});
  @override Widget build(BuildContext context)=>Material(color:color,child:Padding(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
    child:Row(children:[Icon(icon,size:18),const SizedBox(width:8),Expanded(child:Text(text,style:Theme.of(context).textTheme.bodySmall)),if(action!=null)action!]),
  ));
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

String _extension(String platform)=>switch(platform){'windows'=>'.msix','appimage'=>'.AppImage','apk'=>'.apk',_=>''};

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
