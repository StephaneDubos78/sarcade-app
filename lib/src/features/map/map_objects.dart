/// Lot 3 « objets de la carte » (30 Oct 2026): small pieces of the
/// « Affichage » tab kept out of operational_map_page.dart.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/position.dart';

/// « Voir la liste » on the right of the « Points d'intérêt (n) » line,
/// hidden without any point (card « Bouton Fond et affichage », 30 Oct 2026).
Widget? poiSeeListLink(int count,{required VoidCallback onTap})=>count==0?null:OutlinedButton.icon(key:const ValueKey('poi-see-list'),onPressed:onTap,
  icon:const Icon(Icons.list,size:18),label:Text(S.t('poi.seeList')));

/// Stations whose trace is drawn: the pinned ones, and with « Toutes les
/// traces » every operator shown (APRS stations only with their option).
List<String> tracedStations(Iterable<SarcadePosition> onMap,{required Set<String> pinned,required bool all,required bool aprs}){
  final ids=<String>{...pinned};
  if(all){for(final p in onMap){if(!p.isAprs||aprs)ids.add(p.deviceId);}}
  return ids.toList()..sort();
}
