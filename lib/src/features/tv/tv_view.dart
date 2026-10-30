import 'package:flutter/material.dart' show ThemeMode;
import 'package:latlong2/latlong.dart';

/// View of the map of this device, copied onto a TV by « Envoyer ma vue »
/// (29 October 2026): centre, zoom and base map.
typedef TvView=({LatLng center,double zoom,String basemapId,String? tileUrl,String attribution,String basemapName});

/// Set by the map page while it is open; null elsewhere.
TvView? Function()? currentMapView;

/// Step 2 (decision of 29 Oct 2026, 12 h 12): settings applied by the TV,
/// not a screenshot — layers shown, opacity per layer, Messages panel.
typedef TvOptions=({Map<String,bool> layers,Map<String,double> opacity,bool messages});
TvOptions? Function()? currentMapOptions;

/// Day / night mode of this device (Paramètres › Affichage), pushed to the
/// whole TV page with the view (lot 7, 30 Oct 2026).
String tvThemeName(ThemeMode m)=>switch(m){ThemeMode.light=>'day',ThemeMode.dark=>'night',_=>'auto'};

Map<String,dynamic> tvViewJson(TvView v,{TvOptions? options,String? from,ThemeMode? theme})=>{
  if(theme!=null)'theme':tvThemeName(theme),
  // Small « Vue de <terminal> » banner of the TV (30 Oct 2026).
  if(from!=null&&from.trim().isNotEmpty)'from':from.trim().length>64?from.trim().substring(0,64):from.trim(),
  if(options!=null)...{
    'layers':options.layers,
    'opacity':{for(final e in options.opacity.entries)e.key:double.parse(e.value.clamp(0.1,1.0).toStringAsFixed(2))},
    'messages':options.messages,
  },
  'lat':v.center.latitude,'lon':v.center.longitude,'zoom':double.parse(v.zoom.toStringAsFixed(2)),
  'basemap':v.basemapId,
  // Only an online https base map can be shown by the TV.
  if(v.tileUrl!=null&&v.tileUrl!.startsWith('https://'))'tile_url':v.tileUrl,
  'attribution':v.attribution,
};

/// Opacity keys sent to the TV (one per layer; the server also reads the
/// former ops / draw / brg / ref).
const tvOpacityKeys=['ops','aprs','draw','brg','high','relay'];

/// Layers listed in the summary of « Envoyer ma vue » (key of the view,
/// key of the text); « offline » is a filter, not listed.
const tvLayerLabels={'operators':'chips.operators','aprs':'APRS','drawings':'chips.drawings','bearings':'chips.bearings',
  'highpoints':'refs.highPoints','relays':'refs.relays'};

/// Keys of the layers shown, in the order of [tvLayerLabels].
List<String> tvShownLayers(Map<String,bool> layers)=>[for(final k in tvLayerLabels.keys)if(layers[k]==true)k];

/// « 30/10 à 14 h 16 » (« 30/10 at 14:16 » in English) from epoch seconds.
String tvWhen(Object? seconds,{String lang='fr'}){
  if(seconds is! num)return '';
  final d=DateTime.fromMillisecondsSinceEpoch((seconds*1000).toInt()).toLocal();
  String two(int v)=>v.toString().padLeft(2,'0');
  return lang=='fr'?'${two(d.day)}/${two(d.month)} à ${d.hour} h ${two(d.minute)}':'${two(d.day)}/${two(d.month)} at ${two(d.hour)}:${two(d.minute)}';
}

/// Screens of the list: the active ones, plus the expired or revoked ones
/// with « Afficher les anciens ».
/// Title of a screen in the list: its name, else « Code ABC123 » (screens
/// paired before lot 7).
String tvScreenTitle(Map<String,dynamic> d,String codeLabel){
  final n='${d['name']??''}'.trim();
  return n.isNotEmpty?n:'$codeLabel ${d['code']??''}';
}

List<Map<String,dynamic>> tvVisibleScreens(List<Map<String,dynamic>> list,{required bool showOld})=>
  [for(final d in list)if(showOld||d['active']==true)d];
