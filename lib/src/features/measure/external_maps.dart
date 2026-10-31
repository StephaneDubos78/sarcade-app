import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/strings.dart';

/// Apps that send the position to Google (warning, may be hidden).
const trackingApps={'google_maps','waze'};

/// Link opening [app] on the point, or null when the app has no link on this
/// platform. Organic Maps and OsmAnd first: offline, no advertising.
String? appLink(String app,LatLng p,String label,{required bool android,required bool ios}){
  final lat=p.latitude.toStringAsFixed(6), lon=p.longitude.toStringAsFixed(6);
  final name=Uri.encodeComponent(label);
  return switch(app){
    'organic_maps'=>(android||ios)?'om://map?ll=$lat,$lon&n=$name':null,
    'osmand'=>'https://osmand.net/map?pin=$lat,$lon#16/$lat/$lon',
    'apple_maps'=>ios?'maps://?daddr=$lat,$lon&q=$name':'https://maps.apple.com/?daddr=$lat,$lon&q=$name',
    'google_maps'=>'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
    'waze'=>'https://waze.com/ul?ll=$lat,$lon&navigate=yes',
    _=>null,
  };
}

/// Store page of an app the organisation recommends, when it is missing.
String? storeLink(String app,{required bool android}){
  if(!android)return null;
  return switch(app){'organic_maps'=>'https://play.google.com/store/apps/details?id=app.organicmaps',
    'osmand'=>'https://play.google.com/store/apps/details?id=net.osmand',
    'google_maps'=>'https://play.google.com/store/apps/details?id=com.google.android.apps.maps',
    'waze'=>'https://play.google.com/store/apps/details?id=com.waze',_=>null};
}

/// Applications offered by « Ouvrir dans… » (card « Navigation : lancer
/// Waze, Google Maps ou une autre application », 31 Oct 2026): Waze and
/// Google Maps on their own lines, then the offline ones; Plans on iPhone;
/// on Android « Autre application » keeps the system chooser (geo:); on a
/// computer or a browser Google Maps and OpenStreetMap in the browser.
List<String> openInChoices({required bool android,required bool ios,bool hideTracking=false})=>[
  if(!hideTracking)...['waze','google_maps'],
  if(android||ios)...['organic_maps','osmand'],
  if(ios)'apple_maps',
  if(android)'other',
  if(!android&&!ios)'openstreetmap',
];

/// Device preference: the application always used (empty: ask).
const navAppMineKey='nav_app_mine';
/// The warning on Google / Waze, once per device.
const extWarnedKey='ext_warned';

Future<bool> _launch(String url) async {
  try{return await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);}catch(_){return false;}
}

/// Link of [app] (with « other » and « openstreetmap »).
String? openInLink(String app,LatLng p,String label,{required bool android,required bool ios}){
  final lat=p.latitude.toStringAsFixed(6), lon=p.longitude.toStringAsFixed(6);
  return switch(app){
    'other'=>'geo:$lat,$lon?q=$lat,$lon(${Uri.encodeComponent(label)})',
    'openstreetmap'=>'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon',
    'osmand' when ios=>'osmandmaps://navigate?lat=$lat&lon=$lon&z=16&title=${Uri.encodeComponent(label)}',
    _=>appLink(app,p,label,android:android,ios:ios),
  };
}

/// Navigation level 1 (note « Navigation »): « Open in… » another app.
/// [app]: application chosen by the organisation (`operator` = the
/// operator's choice); [hideTracking]: Google Maps and Waze hidden.
/// [prefs] (device store) keeps « Toujours ouvrir avec … » and the warning.
Future<void> openInOtherApp(BuildContext context,LatLng p,String label,{String app='operator',bool hideTracking=false,
    String? Function(String key)? readPref,Future<void> Function(String key,String? value)? writePref}) async {
  final messenger=ScaffoldMessenger.of(context);
  final android=!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  final ios=!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS;
  Future<bool> openApp(String a) async {
    if(trackingApps.contains(a)&&readPref?.call(extWarnedKey)!='1'){
      messenger.showSnackBar(SnackBar(content:Text(S.t('ext.warningAll'))));
      await writePref?.call(extWarnedKey,'1');
    }
    final link=openInLink(a,p,label,android:android,ios:ios);
    if(link==null)return false;
    if(await _launch(link))return true;
    final store=storeLink(a,android:android);
    messenger.showSnackBar(SnackBar(content:Text(S.t('ext.notInstalled',{'app':S.t('ext.app.$a')})),
      action:store==null?null:SnackBarAction(label:S.t('ext.install'),onPressed:()=>_launch(store))));
    return false;
  }
  // Application chosen by the organisation, then the one of the operator.
  final forced=app!='operator'?app:(readPref?.call(navAppMineKey)??'');
  if(forced.isNotEmpty&&openInChoices(android:android,ios:ios).contains(forced)){
    await openApp(forced);
    return;
  }
  if(!context.mounted)return;
  final choices=openInChoices(android:android,ios:ios,hideTracking:hideTracking);
  var always=false;
  final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>StatefulBuilder(builder:(c,set)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Padding(padding:const EdgeInsets.fromLTRB(16,0,16,4),child:Align(alignment:Alignment.centerLeft,child:Text(S.t('ext.open'),style:Theme.of(c).textTheme.titleMedium))),
    for(final a in choices)ListTile(key:ValueKey('open-in-$a'),leading:Icon(a=='waze'||a=='google_maps'?Icons.navigation_outlined:a=='other'?Icons.apps:Icons.map_outlined),
      title:Text(S.t('ext.app.$a')),
      subtitle:a=='organic_maps'||a=='osmand'?Text(S.t('ext.recommended')):trackingApps.contains(a)?Text(S.t('ext.warningShort')):null,
      onTap:()=>Navigator.pop(c,a)),
    CheckboxListTile(key:const ValueKey('open-in-always'),value:always,onChanged:(v)=>set(()=>always=v??false),
      controlAffinity:ListTileControlAffinity.leading,title:Text(S.t('ext.always'))),
  ]))));
  if(choice==null)return;
  if(always&&choice!='other')await writePref?.call(navAppMineKey,choice);
  final ok=await openApp(choice);
  if(!ok&&!android&&!ios){
    if(!await _launch(openInLink('openstreetmap',p,label,android:false,ios:false)!))messenger.showSnackBar(SnackBar(content:Text(S.t('ext.failed'))));
  }
}
