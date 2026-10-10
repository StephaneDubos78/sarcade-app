import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import '../../platform/platform_services.dart';
import '../../services/sarcade_api.dart';
import 'route_models.dart';
import 'routes_controller.dart';
import 'routes_layers.dart';

/// Side panel of the routes: list, waypoints with legs and cumulated
/// lengths, passages, assignment, GPX export, road closures.
class RoutesPanel extends StatelessWidget {
  final RoutesController controller; final SarcadeApi api; final String actorId;
  final String? selectedRouteId; final String? drawingRouteId;
  final List<CommGroup> groups;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String?> onDraw;
  final VoidCallback onDrawClosure;
  final void Function(LatLng point,String label) onNavigate;
  final ValueChanged<List<LatLng>> onFocus;
  const RoutesPanel({super.key,required this.controller,required this.api,required this.actorId,required this.selectedRouteId,
    required this.drawingRouteId,required this.groups,required this.onSelect,required this.onDraw,required this.onDrawClosure,
    required this.onNavigate,required this.onFocus});

  @override Widget build(BuildContext context){
    final selected=selectedRouteId==null?null:controller.route(selectedRouteId!);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(14,8,6,0),child:Row(children:[
        Expanded(child:Text(S.t('routes.title'),style:Theme.of(context).textTheme.titleMedium)),
        IconButton(tooltip:S.t('routes.refresh'),onPressed:controller.refresh,icon:const Icon(Icons.refresh)),
        IconButton(tooltip:S.t('routes.new'),onPressed:()=>_newRoute(context),icon:const Icon(Icons.add_road)),
        if(isPco(actorId))IconButton(tooltip:S.t('closures.new'),onPressed:onDrawClosure,icon:const Icon(Icons.block)),
      ])),
      Expanded(child:selected==null?_list(context):_details(context,selected)),
    ]);
  }

  Widget _list(BuildContext context){
    final routes=controller.routes, closures=controller.closures;
    return ListView(children:[
      if(routes.isEmpty)Padding(padding:const EdgeInsets.all(16),child:Text(S.t('routes.empty'))),
      for(final r in routes)ListTile(
        leading:Icon(Icons.route,color:Color(r.color)),
        title:Text(r.name),
        subtitle:Text('${controller.ordered(r).length} ${S.t('routes.points')} · ${formatDistance(_total(r))}'
          '${r.assigned?' · ${S.t('routes.assigned')}':''}'),
        onTap:(){onSelect(r.id);onFocus(controller.ordered(r).map((w)=>w.point).toList());},
      ),
      if(closures.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(16,16,16,4),child:Text(S.t('closures.title'),style:Theme.of(context).textTheme.titleSmall)),
      for(final c in closures)ListTile(
        leading:Icon(Icons.block,color:c.active?Colors.red:Colors.grey),
        title:Text(c.label),
        subtitle:Text(c.active?S.t('closures.active'):S.t('closures.lifted')),
        onTap:()=>onFocus(c.points),
        trailing:isPco(actorId)?TextButton(onPressed:()=>controller.setClosureActive(c,!c.active),
          child:Text(c.active?S.t('closures.lift'):S.t('closures.restore'))):null,
      ),
    ]);
  }

  double _total(RoutePlan r){final l=legLengths(controller.ordered(r));return l.isEmpty?0:l.last.cumulative;}

  Widget _details(BuildContext context,RoutePlan r){
    final ordered=controller.ordered(r);
    final lengths=legLengths(ordered);
    final passed=passedWaypoints(controller.passages,r.id);
    final editable=r.canEdit(actorId);
    final drawing=drawingRouteId==r.id;
    final group=groups.where((g)=>g.id==r.assignedGroupId).firstOrNull;
    return ListView(children:[
      ListTile(
        leading:IconButton(tooltip:S.t('common.close'),onPressed:()=>onSelect(null),icon:const Icon(Icons.arrow_back)),
        title:Text(r.name,style:const TextStyle(fontWeight:FontWeight.bold)),
        subtitle:Text('${S.t('routes.profile.${r.profile}')} · ${S.t('routes.leg.${r.defaultLegMode}')} · ${formatDistance(lengths.isEmpty?0:lengths.last.cumulative)}'
          '${group!=null?'\n${S.t('routes.assignedTo',{'name':group.name})}':''}'),
        isThreeLine:group!=null,
      ),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Wrap(spacing:6,runSpacing:6,children:[
        if(editable)FilterChip(avatar:const Icon(Icons.add_location_alt_outlined,size:18),label:Text(drawing?S.t('routes.stopAdding'):S.t('routes.addPoints')),
          selected:drawing,onSelected:(_)=>onDraw(drawing?null:r.id)),
        ActionChip(avatar:const Icon(Icons.download,size:18),label:const Text('GPX'),onPressed:()=>_gpx(context,r)),
        if(editable)ActionChip(avatar:const Icon(Icons.groups,size:18),label:Text(S.t('routes.assign')),onPressed:()=>_assign(context,r)),
        if(ordered.any((w)=>w.legNeedsRouting))ActionChip(avatar:const Icon(Icons.alt_route,size:18),label:Text(S.t('routes.computeLegs')),
          onPressed:()=>api.computeLegs(controller.eventId,r.id).catchError((_){})),
        if(editable)ActionChip(avatar:const Icon(Icons.delete_outline,size:18),label:Text(S.t('routes.delete')),onPressed:()=>_deleteRoute(context,r)),
      ])),
      if(!editable)Padding(padding:const EdgeInsets.all(12),child:Text(S.t('routes.readOnly'),style:Theme.of(context).textTheme.bodySmall)),
      if(drawing)Padding(padding:const EdgeInsets.all(12),child:Text(S.t('routes.tapToAdd'),style:Theme.of(context).textTheme.bodySmall)),
      for(var i=0;i<ordered.length;i++)ListTile(
        dense:true,
        leading:Icon(waypointIcon(ordered[i].type),color:passed.contains(ordered[i].id)?Colors.green.shade700:Color(r.color)),
        title:Text('${ordered[i].name} · ${S.t('waypoint.${ordered[i].type}')}'),
        subtitle:Text([
          if(i>0)'${S.t('routes.leg')} ${formatDistance(lengths[i].leg)}${ordered[i].legNeedsRouting?' (${S.t('routes.pending')})':''}',
          if(i>0)'${S.t('routes.cumulative')} ${formatDistance(lengths[i].cumulative)}',
          if(ordered[i].comment.isNotEmpty)ordered[i].comment,
        ].join(' · ')),
        onTap:()=>onFocus([ordered[i].point]),
        trailing:PopupMenuButton<String>(onSelected:(v)=>_waypointAction(context,r,ordered[i],v),itemBuilder:(_)=>[
          PopupMenuItem(value:'navigate',child:Text(S.t('nav.goHere'))),
          PopupMenuItem(value:'passage',child:Text(S.t('routes.markPassage'))),
          PopupMenuItem(value:'report',child:Text(S.t('routes.report'))),
          if(editable)...[
            PopupMenuItem(value:'edit',child:Text(S.t('routes.editPoint'))),
            if(i>0)PopupMenuItem(value:'up',child:Text(S.t('routes.up'))),
            if(i<ordered.length-1)PopupMenuItem(value:'down',child:Text(S.t('routes.down'))),
            PopupMenuItem(value:'delete',child:Text(S.t('routes.deletePoint'))),
          ],
        ]),
      ),
    ]);
  }

  Future<void> _waypointAction(BuildContext context,RoutePlan r,Waypoint w,String action) async {
    final messenger=ScaffoldMessenger.of(context);
    switch(action){
      case 'navigate': onNavigate(w.point,w.name);
      case 'passage': await controller.recordPassage(w,mode:'manual');
        messenger.showSnackBar(SnackBar(content:Text(S.t('routes.passageRecorded',{'name':w.name}))));
      case 'report':
        final reason=await _askText(context,S.t('routes.reportReason'),'');
        if(reason==null||reason.trim().isEmpty)return;
        try{await controller.api.reportWaypoint(controller.eventId,r.id,controller.actorId,w.id,reason.trim());
          messenger.showSnackBar(SnackBar(content:Text(S.t('routes.reported'))));}
        catch(_){messenger.showSnackBar(SnackBar(content:Text(S.t('routes.reportFailed'))));}
      case 'edit': if(context.mounted)await _editWaypoint(context,w);
      case 'up': await controller.moveWaypoint(w,-1);
      case 'down': await controller.moveWaypoint(w,1);
      case 'delete': await controller.deleteWaypoint(w);
    }
  }

  Future<void> _editWaypoint(BuildContext context,Waypoint w) async {
    final name=TextEditingController(text:w.name), comment=TextEditingController(text:w.comment);
    var type=w.type; var radius=w.radiusM; var legMode=w.legMode;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('routes.editPoint')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,maxLength:40,decoration:InputDecoration(labelText:S.t('groups.name'))),
        DropdownButtonFormField<String>(initialValue:type,decoration:InputDecoration(labelText:S.t('routes.pointType')),
          items:[for(final t in waypointTypes)DropdownMenuItem(value:t,child:Text(S.t('waypoint.$t')))],onChanged:(v)=>set(()=>type=v??type)),
        DropdownButtonFormField<String>(initialValue:legMode,decoration:InputDecoration(labelText:S.t('routes.legMode')),
          items:[for(final m in const ['straight','paths'])DropdownMenuItem(value:m,child:Text(S.t('routes.leg.$m')))],onChanged:(v)=>set(()=>legMode=v??legMode)),
        const SizedBox(height:8),
        Text(S.t('routes.radius',{'m':radius.round()})),
        Slider(value:radius.clamp(5,1000),min:5,max:300,divisions:59,onChanged:(v)=>set(()=>radius=v)),
        TextField(controller:comment,maxLength:300,decoration:InputDecoration(labelText:S.t('routes.comment'))),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.save')))],
    )));
    if(ok==true&&name.text.trim().isNotEmpty){
      await controller.updateWaypoint(w,{'name':name.text.trim(),'type':type,'radius_m':radius.roundToDouble(),
        'comment':comment.text.trim(),'leg_mode':legMode});
    }
  }

  Future<void> _newRoute(BuildContext context) async {
    final name=TextEditingController();
    var profile='foot', legMode='straight';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t('routes.new')),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,autofocus:true,maxLength:80,decoration:InputDecoration(labelText:S.t('groups.name'))),
        DropdownButtonFormField<String>(initialValue:profile,decoration:InputDecoration(labelText:S.t('routes.profile')),
          items:[for(final p in const ['foot','vehicle'])DropdownMenuItem(value:p,child:Text(S.t('routes.profile.$p')))],onChanged:(v)=>set(()=>profile=v??profile)),
        DropdownButtonFormField<String>(initialValue:legMode,decoration:InputDecoration(labelText:S.t('routes.legMode')),
          items:[for(final m in const ['straight','paths'])DropdownMenuItem(value:m,child:Text(S.t('routes.leg.$m')))],onChanged:(v)=>set(()=>legMode=v??legMode)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.ok')))],
    )));
    final text=name.text.trim();
    if(ok!=true||text.isEmpty)return;
    final r=await controller.createRoute(name:text,profile:profile,legMode:legMode);
    onSelect(r.id);
    onDraw(r.id);
  }

  Future<void> _assign(BuildContext context,RoutePlan r) async {
    final choice=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:Text(S.t('routes.assign')),children:[
      SimpleDialogOption(onPressed:()=>Navigator.pop(c,''),child:Text(S.t('routes.unassigned'))),
      for(final g in sortedGroups(groups))SimpleDialogOption(onPressed:()=>Navigator.pop(c,g.id),child:Text(g.name)),
    ]));
    if(choice==null)return;
    final group=groups.where((g)=>g.id==choice).firstOrNull;
    await controller.updateRoute(r,{'assigned_group_id':choice.isEmpty?null:choice,'assigned_team_id':group?.teamId,
      'status':choice.isEmpty?'draft':'active'});
  }

  Future<void> _deleteRoute(BuildContext context,RoutePlan r) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(content:Text(S.t('routes.deleteConfirm',{'name':r.name})),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.ok')))]));
    if(ok!=true)return;
    onSelect(null);
    await controller.deleteRoute(r);
  }

  Future<void> _gpx(BuildContext context,RoutePlan r) async {
    final messenger=ScaffoldMessenger.of(context);
    try{
      final bytes=await api.download('/api/v0.1/events/${controller.eventId}/routes/${r.id}.gpx');
      final path=await saveFile('${r.name}.gpx',bytes,mimeType:'application/gpx+xml');
      messenger.showSnackBar(SnackBar(content:Text(S.t('routes.gpxSaved')),
        action:!canOpenSavedFiles?null:SnackBarAction(label:S.t('common.ok'),onPressed:()=>openSavedFile(path))));
    }catch(_){
      messenger.showSnackBar(SnackBar(content:Text(S.t('routes.gpxFailed'))));
    }
  }
}

Future<String?> _askText(BuildContext context,String title,String initial){
  final controller=TextEditingController(text:initial);
  return showDialog<String>(context:context,builder:(c)=>AlertDialog(
    title:Text(title),
    content:TextField(controller:controller,autofocus:true,maxLength:300),
    actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(c,controller.text),child:Text(S.t('common.ok')))],
  )).whenComplete(controller.dispose);
}

/// Label of a new road closure, asked to the PCO.
Future<String?> askClosureLabel(BuildContext context)=>_askText(context,S.t('closures.label'),'');
