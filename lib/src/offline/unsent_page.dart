import 'dart:convert';
import 'package:flutter/material.dart';
import '../features/map/drawing/map_feature.dart';
import '../l10n/strings.dart';
import '../platform/platform_services.dart';
import 'outbox_policy.dart';
import 'sync_service.dart';

/// « Éléments non envoyés » (« Robustesse de la synchronisation »): every
/// item that cannot leave, with its reason, and what the operator can do.
class UnsentPage extends StatefulWidget {
  final OfflineSyncService sync; final String actorId;
  const UnsentPage({super.key,required this.sync,required this.actorId});
  @override State<UnsentPage> createState()=>_UnsentPageState();
}

class _UnsentPageState extends State<UnsentPage> {
  OfflineSyncService get _sync=>widget.sync;

  List<Map<String,dynamic>> _items(){
    final now=DateTime.now().toUtc();
    final all=_sync.store.pending().where((op)=>isUnsent(op,_sync.server,_sync.eventId,now)).toList();
    all.sort((a,b)=>'${a['client_time']}'.compareTo('${b['client_time']}'));
    return all;
  }

  String _age(Map<String,dynamic> op){
    final t=DateTime.tryParse('${op['client_time']}');
    if(t==null)return '';
    final d=DateTime.now().toUtc().difference(t.toUtc());
    if(d.inDays>0)return '${d.inDays} j';
    if(d.inHours>0)return '${d.inHours} h';
    return '${d.inMinutes} min';
  }

  bool _here(Map<String,dynamic> op)=>belongsTo(op,_sync.server,_sync.eventId);

  Future<void> _run(Future<void> Function() action) async {
    await action();
    if(mounted)setState((){});
  }

  Future<void> _export(Map<String,dynamic> op) async {
    final messenger=ScaffoldMessenger.of(context);
    final isFeature=op['object_type']=='map_feature'&&op['payload'] is Map;
    Object content=wire(op);
    var ext='json', mime='application/json';
    if(isFeature){
      try{
        content=featureCollection([MapFeature.fromJson(Map<String,dynamic>.from(op['payload'] as Map))]);
        ext='geojson'; mime='application/geo+json';
      }catch(_){/* kept as JSON */}
    }
    final name='sarcade-non-envoye-${op['object_type']}-${op['object_id']}.$ext'.replaceAll(RegExp(r'[\\/:*?"<>|]'),'_');
    try{
      final path=await saveFile(name,utf8.encode(const JsonEncoder.withIndent('  ').convert(content)),mimeType:mime);
      messenger.showSnackBar(SnackBar(content:Text(S.t('unsent.exported',{'path':path}))));
    }catch(_){
      messenger.showSnackBar(SnackBar(content:Text(S.t('unsent.exportFailed'))));
    }
  }

  Future<void> _delete(Map<String,dynamic> op) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('unsent.delete')),
      content:Text('${S.t('type.${op['object_type']}')} · ${itemSummary(op)}\n\n${S.t('unsent.deleteConfirm')}'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('unsent.delete'))),
      ]));
    if(ok==true)await _run(()=>_sync.discard(op,widget.actorId));
  }

  @override
  Widget build(BuildContext context){
    final items=_items();
    final retryable=items.where(_here).toList();
    return Scaffold(
      appBar:AppBar(title:Text('${S.t('unsent.title')} (${items.length})'),actions:[
        if(retryable.isNotEmpty)TextButton.icon(
          onPressed:()=>_run(() async {for(final op in retryable){await _sync.store.updatePending(resetForRetry(op));}await _sync.syncNow();}),
          icon:const Icon(Icons.refresh),label:Text(S.t('unsent.retryAll'))),
      ]),
      body:items.isEmpty
        ? Center(child:Text(S.t('unsent.empty')))
        : ListView.separated(
            itemCount:items.length,
            separatorBuilder:(_,_)=>const Divider(height:1),
            itemBuilder:(context,i){
              final op=items[i];
              final here=_here(op);
              final server=itemServer(op);
              final where=<String>[
                if(server!=null&&server!=normalServer(_sync.server))S.t('unsent.otherServer',{'server':server}),
                if(op['event_id']!=_sync.eventId)S.t('unsent.otherEvent',{'event':op['event_id']}),
              ];
              final details=<String>[
                ...where,
                if(!here)S.t('unsent.waitsReturn'),
                if(reasonOf(op)!=null)reasonOf(op)!,
                '${S.t('unsent.attempts',{'n':attempts(op)})} · ${S.t('unsent.since',{'age':_age(op)})}',
              ];
              return ListTile(
                leading:Icon(here?Icons.error_outline:Icons.schedule,color:here?Colors.deepOrange:Colors.blueGrey),
                title:Text('${S.t('type.${op['object_type']}')}${itemSummary(op).isEmpty?'':' · ${itemSummary(op)}'}',maxLines:2,overflow:TextOverflow.ellipsis),
                subtitle:Text(details.join('\n')),
                isThreeLine:details.length>1,
                trailing:PopupMenuButton<String>(
                  onSelected:(v){switch(v){
                    case 'retry':_run(()=>_sync.retry(op));
                    case 'attach':_run(()=>_sync.attachHere(op));
                    case 'export':_export(op);
                    case 'delete':_delete(op);
                  }},
                  itemBuilder:(_)=>[
                    if(here)PopupMenuItem(value:'retry',child:ListTile(leading:const Icon(Icons.refresh),title:Text(S.t('unsent.retry')))),
                    if(!here&&canAttach(op))PopupMenuItem(value:'attach',child:ListTile(leading:const Icon(Icons.move_down),title:Text(S.t('unsent.attach')))),
                    PopupMenuItem(value:'export',child:ListTile(leading:const Icon(Icons.download),title:Text(S.t('unsent.export')))),
                    PopupMenuItem(value:'delete',child:ListTile(leading:const Icon(Icons.delete_outline),title:Text(S.t('unsent.delete')))),
                  ],
                ),
              );
            }),
    );
  }
}
