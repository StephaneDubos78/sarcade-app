/// Sheet of a waypoint touched on the map (card « Itinéraires, point de
/// passage introuvable sur la carte », validated on 30 Oct 2026, 3 h 15):
/// route and point, then Modifier, Déplacer, Supprimer le point (author of
/// the route or PCO) and Ouvrir l'itinéraire.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco;
import 'route_models.dart';
import 'routes_layers.dart';

enum WaypointAction { edit, move, delete, open }

/// Same rule as the other objects: the author of the route or the PCO.
bool canEditWaypointOf(RoutePlan r,String actor)=>isPco(actor)||(r.createdBy.isNotEmpty&&r.createdBy==actor);

Future<WaypointAction?> showWaypointSheet(BuildContext context,RoutePlan r,Waypoint w,{required String actor}){
  final can=canEditWaypointOf(r,actor);
  return showModalBottomSheet<WaypointAction>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(leading:Icon(waypointIcon(w.type),color:Color(r.color),size:30),title:Text(waypointLabel(r,w),style:Theme.of(c).textTheme.titleMedium),
      subtitle:Text([S.t('waypoint.${w.type}'),if(w.comment.isNotEmpty)w.comment].join(' · '))),
    const Divider(height:1),
    if(can)ListTile(key:const ValueKey('wp-edit'),leading:const Icon(Icons.edit_outlined),title:Text(S.t('routes.editPoint')),onTap:()=>Navigator.pop(c,WaypointAction.edit)),
    if(can)ListTile(key:const ValueKey('wp-move'),leading:const Icon(Icons.open_with),title:Text(S.t('routes.movePoint')),onTap:()=>Navigator.pop(c,WaypointAction.move)),
    if(can)ListTile(key:const ValueKey('wp-delete'),leading:Icon(Icons.delete_outline,color:Theme.of(c).colorScheme.error),title:Text(S.t('routes.deletePoint')),
      onTap:()=>Navigator.pop(c,WaypointAction.delete)),
    ListTile(key:const ValueKey('wp-open'),leading:const Icon(Icons.route),title:Text(S.t('routes.open')),onTap:()=>Navigator.pop(c,WaypointAction.open)),
    if(!can)Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Text(S.t('routes.readOnly'),style:Theme.of(c).textTheme.bodySmall)),
  ])));
}
