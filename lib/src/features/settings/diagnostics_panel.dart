/// Paramètres › Diagnostic étoffé (lot 5, validated on 30 Oct 2026,
/// 2 h 58): three blocks. « Cet appareil » (everyone): version / build,
/// local and public address, network, GPS, permissions, waiting items,
/// last synchronisation. « Liaisons » (everyone): server response time,
/// real time, Cloudflare Access (signed in, checked email), APRS-IS and the
/// radio Gateway. « Serveur » (PCO and administrators): general state,
/// version, uptime, components in green / orange / red, processor, memory,
/// disk seen from the container (alert above 80 %), last automatic update
/// and backup. « Copier le rapport ».
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../access/access_manager.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show myRoles;
import '../../offline/sync_service.dart';
import '../../platform/platform_services.dart';
import '../../services/notification_service.dart';
import '../../services/realtime_service.dart';
import '../../services/sarcade_api.dart';
import '../aprs/aprs_models.dart' show linkState;

/// green / orange / red / off → colour of the dot.
Color stateColor(String? s)=>switch(s){'green'||'ok'||'connected'=>Colors.green,'orange'||'degraded'||'waiting'=>Colors.orange,
  'red'||'down'=>Colors.red,_=>Colors.grey};

/// « 3 j 4 h », « 2 h 05 », « 12 min ».
String uptimeLabel(int s){
  final d=s~/86400, h=(s%86400)~/3600, m=(s%3600)~/60;
  if(d>0)return '$d j $h h';
  if(h>0)return '$h h ${m.toString().padLeft(2,'0')}';
  return '$m min';
}

/// Resources line with the alert above 80 %.
String percentLabel(num? pct)=>pct==null?'—':'${pct.toStringAsFixed(0)} %${pct>80?' ⚠':''}';

typedef DiagLine=({String block,String label,String value,String? state});

/// Text of « Copier le rapport »: pure, tested.
String diagnosticsReport(List<DiagLine> lines,{DateTime? at}){
  final b=StringBuffer('SARCADE · ${S.t('settings.tab.diagnostics')} · ${(at??DateTime.now()).toLocal().toString().substring(0,19)}');
  String? block;
  for(final l in lines){
    if(l.block!=block){block=l.block;b..write('\n\n')..write(block.toUpperCase());}
    b..write('\n')..write(l.label)..write(' : ')..write(l.value)..write(l.state==null?'':' [${l.state}]');
  }
  return b.toString();
}

/// Lines of the server block from `/diagnostics/server`.
List<DiagLine> serverLines(Map<String,dynamic> d){
  final block=S.t('diag.server');
  final comps=Map<String,dynamic>.from(d['components'] as Map? ?? {});
  final res=Map<String,dynamic>.from(d['resources'] as Map? ?? {});
  final mem=res['memory'] is Map?Map<String,dynamic>.from(res['memory'] as Map):null;
  final disk=res['disk'] is Map?Map<String,dynamic>.from(res['disk'] as Map):null;
  String pctState(num? p)=>p==null?'off':p>80?'red':p>60?'orange':'green';
  final upd=d['last_update'] is Map?Map<String,dynamic>.from(d['last_update'] as Map):null;
  final bak=d['last_backup'] is Map?Map<String,dynamic>.from(d['last_backup'] as Map):null;
  return [
    (block:block,label:S.t('diag.state'),value:S.t('diag.status.${d['status']??'down'}'),state:'${d['status']}'),
    (block:block,label:S.t('diag.version'),value:'${d['version']??'—'}',state:null),
    (block:block,label:S.t('diag.uptime'),value:d['uptime_s'] is num?uptimeLabel((d['uptime_s'] as num).toInt()):'—',state:null),
    for(final c in const ['database','realtime','tunnel','wakeup','aprs','weather'])
      (block:block,label:S.t('diag.comp.$c'),value:S.t('diag.c.${comps[c]??'off'}'),state:'${comps[c]??'off'}'),
    (block:block,label:S.t('diag.cpu'),value:percentLabel(res['cpu_pct'] as num?),state:pctState(res['cpu_pct'] as num?)),
    (block:block,label:S.t('diag.memory'),value:mem==null?'—':'${percentLabel(mem['pct'] as num?)} · ${mem['used_mb']} / ${mem['total_mb']} Mo',state:pctState(mem?['pct'] as num?)),
    (block:block,label:S.t('diag.disk'),value:disk==null?'—':'${percentLabel(disk['pct'] as num?)} · ${disk['used_gb']} / ${disk['total_gb']} Go',state:pctState(disk?['pct'] as num?)),
    (block:block,label:S.t('diag.lastUpdate'),value:upd==null?S.t('diag.unknown'):'${upd['version']} · ${_date(upd['at'])} · ${upd['status']}',state:null),
    (block:block,label:S.t('diag.lastBackup'),value:bak==null?S.t('diag.unknown'):_date(bak['at']),state:null),
  ];
}

String _date(Object? iso){
  final t=DateTime.tryParse('${iso??''}')?.toLocal(); if(t==null)return '—';
  String two(int v)=>v.toString().padLeft(2,'0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class DiagnosticsPanel extends StatefulWidget {
  final SarcadeApi api; final String server, eventId;
  const DiagnosticsPanel({super.key,required this.api,required this.server,required this.eventId});
  @override State<DiagnosticsPanel> createState()=>_DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends State<DiagnosticsPanel> {
  List<DiagLine> _device=[], _links=[], _server=[]; bool _loading=true; String? _serverError;

  bool get _pco=>myRoles.contains('pco')||myRoles.contains('admin');

  @override void initState(){super.initState();unawaited(_load());}

  Future<void> _load() async {
    setState(()=>_loading=true);
    final dev=S.t('diag.device'), lk=S.t('diag.links');
    // Server response time (and what it sees of this device).
    final sw=Stopwatch()..start();
    Map<String,dynamic>? client;
    try{client=await widget.api.clientDiagnostics().timeout(const Duration(seconds:6));}catch(_){client=null;}
    sw.stop();
    final reached=client!=null;
    final local=await localAddresses();
    String net='—';
    try{final t=await Connectivity().checkConnectivity();net=t.map((e)=>e.name).join(', ');}catch(_){/* unknown */}
    String gps='—', gpsState='off';
    try{
      final perm=await Geolocator.checkPermission();
      final on=await Geolocator.isLocationServiceEnabled();
      gpsState=!on||perm==LocationPermission.denied||perm==LocationPermission.deniedForever?'red':'green';
      final last=on?await Geolocator.getLastKnownPosition():null;
      gps=[S.t(on?'diag.gpsOn':'diag.gpsOff'),S.t('diag.perm.${perm.name}'),if(last!=null)'± ${last.accuracy.round()} m'].join(' · ');
    }catch(_){gps=S.t('diag.gpsNone');}
    bool? notif;
    try{notif=await NotificationService().permissionGranted();}catch(_){notif=null;}
    final sync=OfflineSyncService.active;
    final rt=RealtimeService.active;
    final access=AccessManager.instance.sessionFor(widget.server);
    Map<String,dynamic>? aprs;
    try{aprs=await widget.api.aprsStatus().timeout(const Duration(seconds:5));}catch(_){aprs=null;}
    Map<String,dynamic>? link(String k)=>aprs?[k] is Map?Map<String,dynamic>.from(aprs![k] as Map):null;
    final device=<DiagLine>[
      (block:dev,label:S.t('diag.version'),value:'SARCADE $appVersionFull${appBuild.isEmpty?'':' · $appBuild'}',state:null),
      (block:dev,label:S.t('diag.localIp'),value:local.isEmpty?'—':local.join(', '),state:null),
      (block:dev,label:S.t('diag.publicIp'),value:'${client?['ip']??'—'}',state:null),
      (block:dev,label:S.t('diag.network'),value:net,state:null),
      (block:dev,label:S.t('diag.gps'),value:gps,state:gpsState),
      (block:dev,label:S.t('diag.notifications'),value:S.t(notif==null?'diag.unknown':notif?'diag.allowed':'diag.refused'),state:notif==null?null:notif?'green':'orange'),
      (block:dev,label:S.t('diag.pending'),value:'${sync?.unsent??0}',state:(sync?.unsent??0)>0?'orange':'green'),
      (block:dev,label:S.t('diag.lastSync'),value:sync?.lastServerContact==null?'—':_date(sync!.lastServerContact!.toUtc().toIso8601String()),state:sync==null?null:sync.lastSyncOk?'green':'orange'),
    ];
    final links=<DiagLine>[
      (block:lk,label:S.t('diag.response'),value:reached?'${sw.elapsedMilliseconds} ms':S.t('diag.unreachable'),state:!reached?'red':sw.elapsedMilliseconds>1500?'orange':'green'),
      (block:lk,label:S.t('diag.realtime'),value:S.t(rt?.connected==true?'diag.connected':'diag.disconnected'),state:rt==null?null:rt.connected?'green':'red'),
      (block:lk,label:S.t('diag.access'),value:access==null?S.t(client?['via_cloudflare']==true?'diag.accessNone':'diag.accessLocal')
        :[S.t('diag.connected'),if(access.email!=null)access.email!,if(client?['email']!=null)S.t('diag.emailChecked')].join(' · '),
        state:access==null?(client?['via_cloudflare']==true?'orange':null):'green'),
      (block:lk,label:S.t('aprs.is'),value:S.t('aprs.link.${linkState(link('aprs_is'))}'),state:linkState(link('aprs_is'))),
      (block:lk,label:S.t('aprs.radio'),value:S.t('aprs.link.${linkState(link('radio'))}'),state:linkState(link('radio'))),
    ];
    var server=<DiagLine>[]; String? err;
    if(_pco){
      try{server=serverLines(await widget.api.serverDiagnostics().timeout(const Duration(seconds:8)));}
      on SarcadeHttpException catch(e){err=e.statusCode==403?S.t('diag.serverForbidden'):e.statusCode==404?S.t('diag.serverOld'):'HTTP ${e.statusCode}';}
      catch(_){err=S.t('diag.unreachable');}
    }
    if(!mounted)return;
    setState((){_device=device;_links=links;_server=server;_serverError=err;_loading=false;});
  }

  Widget _block(String title,List<DiagLine> lines,{Widget? footer}){
    final t=Theme.of(context);
    return Card(elevation:0,margin:const EdgeInsets.only(top:12),color:t.colorScheme.surfaceContainerLow,child:Padding(
      padding:const EdgeInsets.symmetric(vertical:6),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.fromLTRB(14,6,14,4),child:Text(title,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w700))),
        // Label kept on one line, value wraps (30 Oct 2026: on iPhone the
        // ListTile trailing squeezed the label into one letter per line).
        for(final l in lines)Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Row(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            SizedBox(width:24,child:l.state==null?null:Padding(padding:const EdgeInsets.only(top:4),
              child:Icon(Icons.circle,size:12,color:stateColor(l.state)))),
            Text(l.label,softWrap:false),
            const SizedBox(width:12),
            Expanded(child:SelectableText(l.value,textAlign:TextAlign.end)),
          ])),
        ?footer,
      ])));
  }

  @override Widget build(BuildContext context){
    final all=[..._device,..._links,..._server];
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.only(top:8),child:Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
        FilledButton.icon(key:const ValueKey('diag-copy'),onPressed:all.isEmpty?null:() async {
          final messenger=ScaffoldMessenger.of(context);
          await Clipboard.setData(ClipboardData(text:diagnosticsReport(all)));
          messenger.showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
        },icon:const Icon(Icons.copy_all),label:Text(S.t('diag.copyReport'))),
        OutlinedButton.icon(onPressed:_loading?null:_load,icon:const Icon(Icons.refresh),label:Text(S.t('diag.refresh'))),
        if(_loading)const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)),
      ])),
      if(_device.isNotEmpty)_block(S.t('diag.device'),_device),
      if(_links.isNotEmpty)_block(S.t('diag.links'),_links),
      if(_pco&&(_server.isNotEmpty||_serverError!=null))_block(S.t('diag.server'),_server,
        footer:_serverError==null?null:Padding(padding:const EdgeInsets.fromLTRB(14,4,14,8),child:Text(_serverError!))),
    ]);
  }
}
