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

/// Navigation level 1 (note « Navigation »): « Open in… » another app.
/// [app]: application chosen by the organisation (`operator` = the
/// operator's choice); [hideTracking]: Google Maps and Waze hidden.
/// Android shows its own chooser (`geo:`), iPhone offers the recognised apps,
/// PC and browser open OpenStreetMap.
Future<void> openInOtherApp(BuildContext context,LatLng p,String label,{String app='operator',bool hideTracking=false}) async {
  final messenger=ScaffoldMessenger.of(context);
  final android=!kIsWeb&&defaultTargetPlatform==TargetPlatform.android;
  final ios=!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS;
  final lat=p.latitude.toStringAsFixed(6), lon=p.longitude.toStringAsFixed(6);
  final name=Uri.encodeComponent(label);
  Future<bool> open(String url)async{
    try{return await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);}catch(_){return false;}
  }
  var ok=false;
  // Application chosen by the organisation: opened directly.
  if(app!='operator'&&(android||ios)){
    final link=appLink(app,p,label,android:android,ios:ios);
    if(link!=null){
      if(trackingApps.contains(app))messenger.showSnackBar(SnackBar(content:Text(S.t('ext.warning'))));
      ok=await open(link);
      if(ok)return;
      final store=storeLink(app,android:android);
      messenger.showSnackBar(SnackBar(content:Text(S.t('ext.notInstalled',{'app':S.t('ext.app.$app')})),
        action:store==null?null:SnackBarAction(label:S.t('ext.install'),onPressed:()=>open(store))));
    }
  }
  if(!context.mounted)return;
  if(android){
    ok=await open('geo:$lat,$lon?q=$lat,$lon($name)');
  }else if(ios){
    final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.map_outlined),title:Text(S.t('ext.app.organic_maps')),subtitle:Text(S.t('ext.recommended')),onTap:()=>Navigator.pop(c,appLink('organic_maps',p,label,android:false,ios:true))),
      ListTile(leading:const Icon(Icons.map_outlined),title:Text(S.t('ext.app.osmand')),subtitle:Text(S.t('ext.recommended')),onTap:()=>Navigator.pop(c,'osmandmaps://navigate?lat=$lat&lon=$lon&z=16&title=$name')),
      ListTile(leading:const Icon(Icons.map),title:Text(S.t('ext.app.apple_maps')),onTap:()=>Navigator.pop(c,appLink('apple_maps',p,label,android:false,ios:true))),
      if(!hideTracking)ListTile(leading:const Icon(Icons.warning_amber),title:const Text('Google Maps / Waze'),subtitle:Text(S.t('ext.warning')),onTap:()=>Navigator.pop(c,'comgooglemaps://?daddr=$lat,$lon')),
    ])));
    if(choice==null)return;
    ok=await open(choice);
  }
  // PC, Chromebook, browser, or no app able to open the link.
  if(!ok)ok=await open('https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon');
  if(!ok)messenger.showSnackBar(SnackBar(content:Text(S.t('ext.failed'))));
}
