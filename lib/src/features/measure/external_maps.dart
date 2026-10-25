import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/strings.dart';

/// Navigation level 1 (note « Navigation »): « Open in… » another app.
/// Android shows its own chooser (Organic Maps, OsmAnd, Google Maps, Waze…);
/// iPhone offers the recognised apps; PC and browser open OpenStreetMap.
/// Organic Maps and OsmAnd come first: they work offline and do not send
/// the position to an advertising company.
Future<void> openInOtherApp(BuildContext context,LatLng p,String label) async {
  final messenger=ScaffoldMessenger.of(context);
  final lat=p.latitude.toStringAsFixed(6), lon=p.longitude.toStringAsFixed(6);
  final name=Uri.encodeComponent(label);
  Future<bool> open(String url)async{
    try{return await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);}catch(_){return false;}
  }
  var ok=false;
  if(!kIsWeb&&defaultTargetPlatform==TargetPlatform.android){
    ok=await open('geo:$lat,$lon?q=$lat,$lon($name)');
  }else if(!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS){
    final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.map_outlined),title:const Text('Organic Maps'),subtitle:Text(S.t('ext.recommended')),onTap:()=>Navigator.pop(c,'om://map?ll=$lat,$lon&n=$name')),
      ListTile(leading:const Icon(Icons.map_outlined),title:const Text('OsmAnd'),subtitle:Text(S.t('ext.recommended')),onTap:()=>Navigator.pop(c,'osmandmaps://navigate?lat=$lat&lon=$lon&z=16&title=$name')),
      ListTile(leading:const Icon(Icons.map),title:Text(S.t('ext.applePlans')),onTap:()=>Navigator.pop(c,'https://maps.apple.com/?daddr=$lat,$lon&q=$name')),
      ListTile(leading:const Icon(Icons.warning_amber),title:const Text('Google Maps / Waze'),subtitle:Text(S.t('ext.warning')),onTap:()=>Navigator.pop(c,'comgooglemaps://?daddr=$lat,$lon')),
    ])));
    if(choice==null)return;
    ok=await open(choice);
  }
  // PC, Chromebook, browser, or no app able to open a « geo: » link.
  if(!ok)ok=await open('https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon');
  if(!ok)messenger.showSnackBar(SnackBar(content:Text(S.t('ext.failed'))));
}
