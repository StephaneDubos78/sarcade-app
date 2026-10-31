/// Menu of a point of the map as a grid (card « Menu du point de la carte
/// en grille », validated on the mock-up on 30 Oct 2026, 1 h 58): location
/// line on top with the coordinates and « Copier », then two rows of
/// icons: Relevé, Point d'intérêt, Envoyer un opérateur (PCO), Mesurer,
/// Y aller, Météo. « Y aller » offers navigating in SARCADE, a route or
/// another application.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../ui/test_ids.dart';
import '../places/readable_place.dart';

/// [info]: the location line touched, fiche « Infos du point » (lot 5).
enum PointAction { bearing, poi, order, measure, navigate, route, external, weather, info, select }

/// Entries of the grid, in the validated order.
List<PointAction> pointMenuEntries({required bool pco,bool adrasec=true})=>[
  // « Relevé » belongs to the ADRASEC module (31 Oct 2026).
  if(adrasec)PointAction.bearing,PointAction.poi,if(pco)PointAction.order,PointAction.measure,PointAction.navigate,PointAction.weather,
  // « Sélectionner une zone » (17 h 36): a rectangle selects the drawn objects.
  PointAction.select];

/// Appui long on (or within ≈ 30 m of) my own position: bearing from the GPS
/// position (decision of 30 Oct 2026, 3 h 05).
const ownPositionRadiusM=30.0;
bool nearOwnPosition(LatLng point,LatLng? me)=>me!=null&&const Distance().as(LengthUnit.Meter,point,me)<=ownPositionRadiusM;

/// [objects]: drawn shapes under the finger, offered first as « Sélectionner
/// … » ([onSelectObject]); the point menu always opens (31 Oct 2026).
Future<PointAction?> showPointMenu(BuildContext context,{required LatLng point,required PlaceDescriber places,required bool pco,bool adrasec=true,required String coordinates,
    List<({String id,String label})> objects=const [],ValueChanged<String>? onSelectObject}) async {
  final choice=await showModalBottomSheet<PointAction>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(
    padding:const EdgeInsets.fromLTRB(16,0,16,12),
    child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      for(final o in objects)ListTile(key:ValueKey('select-${o.id}'),contentPadding:EdgeInsets.zero,leading:const Icon(Icons.highlight_alt),
        title:Text(S.t('point.selectObject',{'name':o.label})),onTap:(){Navigator.pop(c);onSelectObject?.call(o.id);}),
      _LocationLine(point:point,places:places,coordinates:coordinates,onOpen:()=>Navigator.pop(c,PointAction.info)),
      const SizedBox(height:12),
      _Grid(entries:pointMenuEntries(pco:pco,adrasec:adrasec),onPick:(a)=>Navigator.pop(c,a)),
    ]))));
  if(choice!=PointAction.navigate||!context.mounted)return choice;
  return showModalBottomSheet<PointAction>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(leading:const Icon(Icons.navigation_outlined),title:Text(S.t('point.navInApp')),onTap:()=>Navigator.pop(c,PointAction.navigate)),
    ListTile(leading:const Icon(Icons.add_road),title:Text(S.t('point.route')),onTap:()=>Navigator.pop(c,PointAction.route)),
    ListTile(leading:const Icon(Icons.open_in_new),title:Text(S.t('point.otherApp')),onTap:()=>Navigator.pop(c,PointAction.external)),
  ])));
}

IconData _icon(PointAction a)=>switch(a){
  PointAction.bearing=>Icons.track_changes,PointAction.poi=>Icons.add_location_alt_outlined,PointAction.order=>Icons.flag_outlined,
  PointAction.measure=>Icons.straighten,PointAction.navigate=>Icons.directions,PointAction.weather=>Icons.cloud_outlined,
  PointAction.route=>Icons.add_road,PointAction.external=>Icons.open_in_new,PointAction.info=>Icons.info_outline,PointAction.select=>Icons.highlight_alt};

String _label(PointAction a)=>S.t(switch(a){
  PointAction.bearing=>'point.bearing',PointAction.poi=>'point.poi',PointAction.order=>'point.order',
  PointAction.measure=>'point.measure',PointAction.navigate=>'point.go',PointAction.weather=>'point.weather',
  PointAction.route=>'point.route',PointAction.external=>'point.otherApp',PointAction.info=>'info.title',PointAction.select=>'point.selectArea'});

class _Grid extends StatelessWidget {
  final List<PointAction> entries; final ValueChanged<PointAction> onPick;
  const _Grid({required this.entries,required this.onPick});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    // Two rows: three icons per row (four with the PCO entry on the first).
    final perRow=(entries.length/2).ceil();
    Widget cell(PointAction a)=>Expanded(child:withId('point.${a.name}',InkWell(borderRadius:BorderRadius.circular(16),onTap:()=>onPick(a),
      child:Padding(padding:const EdgeInsets.symmetric(vertical:8,horizontal:2),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:52,height:52,decoration:BoxDecoration(color:s.primaryContainer,shape:BoxShape.circle),
          child:Icon(_icon(a),color:s.onPrimaryContainer)),
        const SizedBox(height:6),
        Text(_label(a),textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13)),
      ])))));
    Widget row(List<PointAction> list)=>Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      for(final a in list)cell(a),for(var i=list.length;i<perRow;i++)const Expanded(child:SizedBox.shrink())]);
    return Column(mainAxisSize:MainAxisSize.min,children:[row(entries.take(perRow).toList()),const SizedBox(height:4),row(entries.skip(perRow).toList())]);
  }
}

/// Coordinates and place name, « Copier » on the right; laid out in a row
/// of its own so that no round icon covers it.
class _LocationLine extends StatefulWidget {
  final LatLng point; final PlaceDescriber places; final String coordinates; final VoidCallback onOpen;
  const _LocationLine({required this.point,required this.places,required this.coordinates,required this.onOpen});
  @override State<_LocationLine> createState()=>_LocationLineState();
}

class _LocationLineState extends State<_LocationLine> {
  late final Future<Map<String,dynamic>?> _place=widget.places.describe(widget.point);
  @override Widget build(BuildContext context){
    final coordinates=widget.coordinates;
    final s=Theme.of(context).colorScheme;
    // Touching the line opens the fiche « Infos du point » (lot 5).
    return Material(color:s.surfaceContainerHigh,borderRadius:BorderRadius.circular(12),clipBehavior:Clip.antiAlias,child:InkWell(
      key:const ValueKey('point-info'),onTap:widget.onOpen,child:Padding(padding:const EdgeInsets.fromLTRB(12,6,4,6),
      child:Row(children:[
        Icon(Icons.place_outlined,size:20,color:s.onSurfaceVariant),const SizedBox(width:10),
        Expanded(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(coordinates,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w600,fontFeatures:[FontFeature.tabularFigures()])),
          FutureBuilder<Map<String,dynamic>?>(future:_place,builder:(c,f){final t=placeText(f.data);
            return t==null?const SizedBox.shrink():Text(t,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:13,color:s.onSurfaceVariant));}),
        ])),
        Icon(Icons.chevron_right,color:s.onSurfaceVariant),
        IconButton(tooltip:S.t('common.copy'),icon:const Icon(Icons.copy_outlined),onPressed:(){
          Clipboard.setData(ClipboardData(text:coordinates));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
        }),
      ]))));
  }
}
