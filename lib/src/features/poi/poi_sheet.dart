/// Points of interest (decision of the project owner, 29 Oct 2026, option A):
/// sheet on touch (name, author, time, coordinates), rename, delete with
/// confirmation, send in a message, route to here; everyone changes his own
/// points, the PCO all of them. Pin in the author's drawing colour, never
/// the red kept for the 121.5 MHz beacons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco;
import '../../models/poi.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../bearings/bearing_models.dart' show operatorColor;
import '../measure/coordinates.dart';

/// Colour used instead of a red one (reserved for the beacons).
const poiFallbackColor=0xFF1E88E5;

/// True for a red: hue within 20° of 0 and saturated enough to be read as red.
bool isReservedRed(int argb){
  final hsv=HSVColor.fromColor(Color(argb));
  return hsv.saturation>0.45&&hsv.value>0.35&&(hsv.hue<=20||hsv.hue>=340);
}

/// Colour stored on a new point: the author's drawing colour, red excluded.
int poiColorFor(int drawColor)=>isReservedRed(drawColor)?poiFallbackColor:drawColor;

/// Colour of the pin: stored colour, else derived from the author.
int poiColor(SarcadePoi p){
  final c=p.color??(p.createdBy==null?poiFallbackColor:operatorColor(p.createdBy!));
  return poiColorFor(c);
}

bool canEditPoi(SarcadePoi p,String actor)=>isPco(actor)||(p.createdBy!=null&&p.createdBy==actor);

String poiName(SarcadePoi p)=>(p.label??'').trim().isEmpty?S.t('poi.unnamed'):p.label!.trim();

String poiTime(DateTime t,[DateTime? now]){
  final l=t.toLocal(); final n=(now??DateTime.now()).toLocal();
  String two(int v)=>v.toString().padLeft(2,'0');
  final hm='${two(l.hour)}:${two(l.minute)}';
  return l.year==n.year&&l.month==n.month&&l.day==n.day?hm:'${two(l.day)}/${two(l.month)} $hm';
}

/// Text of « Envoyer en message ».
String poiMessage(SarcadePoi p,CoordFormat format,{int mgrsDigits=4})=>
  S.t('poi.message',{'name':poiName(p),'pos':formatCoordinates(LatLng(p.lat,p.lon),format,mgrsDigits:mgrsDigits)});

Marker poiMarker(SarcadePoi p,VoidCallback onTap)=>Marker(point:LatLng(p.lat,p.lon),width:40,height:40,
  child:Tooltip(message:poiName(p),child:GestureDetector(key:ValueKey('poi-${p.id}'),behavior:HitTestBehavior.opaque,onTap:onTap,
    child:Icon(Icons.location_on,size:38,color:Color(poiColor(p)),shadows:const [Shadow(blurRadius:3,color:Colors.black54)]))));

/// New point of the event, by [actor] in his drawing colour.
Map<String,dynamic> newPoiJson({required String id,required String eventId,required LatLng at,String? label,required String actor,required int drawColor})=>{
  'id':id,'event_id':eventId,'kind':'designated','label':label,'lat':at.latitude,'lon':at.longitude,
  'created_at':DateTime.now().toUtc().toIso8601String(),'created_by':actor,'color':poiColorFor(drawColor)};

/// Applies a point from the server (realtime or change feed): a deleted one
/// leaves the map and the cache. Returns true when [pois] changed.
Future<bool> applyRemotePoi(Map<String,SarcadePoi> pois,LocalStore store,Map<String,dynamic> json,String eventId) async {
  if(json['event_id']!=eventId||json['id']==null)return false;
  if(json['deleted']==true){await store.deletePoi('${json['id']}');return pois.remove(json['id'])!=null;}
  final p=SarcadePoi.fromJson(json);
  await store.cachePoi(p.toJson());
  pois[p.id]=p;
  return true;
}

Future<void> renamePoi(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String label,String actor) async {
  final now=DateTime.now().toUtc().toIso8601String();
  final j=p.toJson()..['label']=label..['updated_by']=actor;
  pois[p.id]=SarcadePoi.fromJson(j);
  await store.cachePoi(j);
  await sync.queue(objectId:p.id,objectType:'poi',action:'update',payload:{'id':p.id,'event_id':p.eventId,'label':label,'updated_by':actor,'updated_at':now});
}

Future<void> deletePoi(Map<String,SarcadePoi> pois,LocalStore store,OfflineSyncService sync,SarcadePoi p,String actor) async {
  pois.remove(p.id);
  await store.deletePoi(p.id);
  await sync.queue(objectId:p.id,objectType:'poi',action:'delete',payload:{'id':p.id,'event_id':p.eventId,'label':p.label,'updated_by':actor,
    'updated_at':DateTime.now().toUtc().toIso8601String()});
}

Future<String?> askPoiName(BuildContext context,SarcadePoi p) async {
  final ctl=TextEditingController(text:p.label??'');
  final r=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('poi.rename')),
    content:TextField(key:const ValueKey('poi-name'),controller:ctl,autofocus:true,maxLength:160,decoration:InputDecoration(labelText:S.t('poi.name')),
      onSubmitted:(v)=>Navigator.pop(c,v.trim())),
    actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(c,ctl.text.trim()),child:Text(S.t('common.save')))]));
  ctl.dispose();
  return r;
}

Future<bool> confirmPoiDelete(BuildContext context,SarcadePoi p) async =>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
  title:Text(S.t('poi.deleteTitle')),content:Text(S.t('poi.deleteBody',{'name':poiName(p)})),
  actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
    FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(c).colorScheme.error),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.delete')))]))==true;

/// The sheet of a point; returns the action chosen: rename, delete, send, route.
Future<String?> showPoiSheet(BuildContext context,SarcadePoi p,{required CoordFormat format,int mgrsDigits=4,required bool canEdit}){
  final pos=formatCoordinates(LatLng(p.lat,p.lon),format,mgrsDigits:mgrsDigits);
  return showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(leading:Icon(Icons.location_on,color:Color(poiColor(p)),size:32),title:Text(poiName(p),style:Theme.of(c).textTheme.titleMedium),
      subtitle:Text([S.t('poi.by',{'who':p.createdBy??S.t('poi.unknownAuthor')}),poiTime(p.createdAt)].join(' · '))),
    ListTile(dense:true,leading:const Icon(Icons.my_location),title:SelectableText(pos)),
    const Divider(height:1),
    if(canEdit)ListTile(leading:const Icon(Icons.edit_outlined),title:Text(S.t('poi.rename')),onTap:()=>Navigator.pop(c,'rename')),
    ListTile(leading:const Icon(Icons.send_outlined),title:Text(S.t('measure.send')),onTap:()=>Navigator.pop(c,'send')),
    ListTile(leading:const Icon(Icons.add_road),title:Text(S.t('routes.toHere')),onTap:()=>Navigator.pop(c,'route')),
    if(canEdit)ListTile(leading:Icon(Icons.delete_outline,color:Theme.of(c).colorScheme.error),title:Text(S.t('common.delete')),onTap:()=>Navigator.pop(c,'delete')),
  ])));
}

/// « Points d'intérêt » in the layers panel: show / hide, then the list.
List<Widget> poiLayerList(BuildContext c,{required List<SarcadePoi> pois,required ValueChanged<SarcadePoi> onOpen}){
  final sorted=[...pois]..sort((a,b)=>b.createdAt.compareTo(a.createdAt));
  return [
    for(final p in sorted)ListTile(dense:true,visualDensity:VisualDensity.compact,
      leading:Icon(Icons.location_on,color:Color(poiColor(p))),title:Text(poiName(p),maxLines:1,overflow:TextOverflow.ellipsis),
      subtitle:Text('${p.createdBy??S.t('poi.unknownAuthor')} · ${poiTime(p.createdAt)}'),onTap:()=>onOpen(p)),
  ];
}
