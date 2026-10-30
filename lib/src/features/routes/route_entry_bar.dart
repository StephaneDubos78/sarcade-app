/// Phone, adding points to an itinerary (card « Itinéraires sur téléphone,
/// saisie des points », validated 30 Oct 2026, 16 h 35; revue d'ergonomie
/// n° 52): the panel folds into this compact bar at the bottom — name,
/// distance, number of points, « Annuler le dernier point », « Terminer » —
/// and the map takes all the rest. The full panel comes back on « Terminer ».
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'route_models.dart';
import 'routes_controller.dart';

/// Phone width: Itinéraires and Résection take the whole screen.
bool sidePanelFullScreen(double screenWidth)=>screenWidth<600;

class RouteEntryBar extends StatelessWidget {
  final RoutesController controller; final RoutePlan route; final VoidCallback onDone;
  const RouteEntryBar({super.key,required this.controller,required this.route,required this.onDone});

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final ordered=controller.ordered(route);
    final lengths=legLengths(ordered);
    final total=lengths.isEmpty?0.0:lengths.last.cumulative;
    return Material(key:const ValueKey('route-entry-bar'),elevation:6,borderRadius:BorderRadius.circular(16),color:t.colorScheme.surface,
      child:Padding(padding:const EdgeInsets.fromLTRB(14,8,8,8),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          Icon(Icons.add_location_alt_outlined,color:Color(route.color)),const SizedBox(width:8),
          Expanded(child:Text(route.name,maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.titleSmall)),
          Text(S.t('routes.entrySummary',{'d':formatDistance(total),'n':ordered.length}),style:t.textTheme.bodySmall),
        ]),
        Text(S.t('routes.tapToAdd'),style:t.textTheme.bodySmall),
        const SizedBox(height:4),
        Row(mainAxisAlignment:MainAxisAlignment.end,children:[
          TextButton.icon(key:const ValueKey('route-undo-point'),onPressed:ordered.isEmpty?null:()=>controller.deleteWaypoint(ordered.last),
            icon:const Icon(Icons.undo),label:Text(S.t('routes.undoPoint'))),
          const SizedBox(width:8),
          FilledButton(key:const ValueKey('route-done'),onPressed:onDone,child:Text(S.t('routes.done'))),
        ]),
      ])));
  }
}
