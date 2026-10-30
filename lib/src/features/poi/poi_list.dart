/// Many points of interest (card « Points d'intérêt nombreux », validated
/// on 30 Oct 2026, 1 h 37): one line in the « Affichage » tab, the list
/// apart (a screen on the phone, a panel on a computer, as Équipes) with
/// search, sort (name, date, distance), filter by icon and by author; a
/// touch centres the map and opens the sheet. On the map, points that
/// overlap form a bubble with their number, opened by zooming in (no new
/// dependency).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../models/poi.dart';
import '../map/drawing/geometry.dart' show distanceM, formatDistance;
import 'poi_icons.dart';
import 'poi_sheet.dart';

enum PoiSort { date, name, distance }

/// Points matching [query] (name, author), [icon] and [author], sorted.
List<SarcadePoi> filterPois(Iterable<SarcadePoi> pois,{String query='',String? icon,String? author,PoiSort sort=PoiSort.date,LatLng? from}){
  final q=query.trim().toLowerCase();
  final out=pois.where((p)=>(q.isEmpty||poiName(p).toLowerCase().contains(q)||(p.createdBy??'').toLowerCase().contains(q))
    &&(icon==null||(p.icon??'pin')==icon)&&(author==null||(p.createdBy??'')==author)).toList();
  switch(sort){
    case PoiSort.date: out.sort((a,b)=>b.createdAt.compareTo(a.createdAt));
    case PoiSort.name: out.sort((a,b)=>poiName(a).toLowerCase().compareTo(poiName(b).toLowerCase()));
    case PoiSort.distance:
      if(from!=null){out.sort((a,b)=>distanceM(from,LatLng(a.lat,a.lon)).compareTo(distanceM(from,LatLng(b.lat,b.lon))));}
  }
  return out;
}

/// Groups of points closer than [cellPx] on screen; one group per cell.
List<List<SarcadePoi>> clusterPois(List<SarcadePoi> pois,Offset Function(LatLng) project,{double cellPx=56}){
  final cells=<(int,int),List<SarcadePoi>>{};
  for(final p in pois){
    final o=project(LatLng(p.lat,p.lon));
    (cells[((o.dx/cellPx).floor(),(o.dy/cellPx).floor())]??=[]).add(p);
  }
  return cells.values.toList();
}

/// Points on the map, grouped when they overlap; from [clusterUntilZoom]
/// every point alone. A bubble zooms in on its group.
class PoiClusterLayer extends StatelessWidget {
  final List<SarcadePoi> pois; final void Function(SarcadePoi) onTap; final double clusterUntilZoom;
  const PoiClusterLayer({super.key,required this.pois,required this.onTap,this.clusterUntilZoom=17});
  @override Widget build(BuildContext context){
    final camera=MapCamera.of(context);
    final groups=camera.zoom>=clusterUntilZoom?[for(final p in pois)[p]]:clusterPois(pois,(l)=>camera.projectAtZoom(l));
    final s=Theme.of(context).colorScheme;
    return MarkerLayer(markers:[for(final g in groups)
      if(g.length==1)poiMarker(g.first,()=>onTap(g.first))
      else _bubble(context,camera,g,s)]);
  }
  Marker _bubble(BuildContext context,MapCamera camera,List<SarcadePoi> g,ColorScheme s){
    final lat=g.map((p)=>p.lat).reduce((a,b)=>a+b)/g.length, lon=g.map((p)=>p.lon).reduce((a,b)=>a+b)/g.length;
    final size=36.0+math.min(14.0,g.length.toDouble());
    return Marker(point:LatLng(lat,lon),width:size,height:size,child:Tooltip(message:'${S.t('poi.layer')} · ${g.length}',
      child:GestureDetector(key:ValueKey('poi-cluster-${g.length}'),onTap:(){
        final pts=[for(final p in g)LatLng(p.lat,p.lon)];
        final b=LatLngBounds.fromPoints(pts);
        if(b.north-b.south<1e-6&&b.east-b.west<1e-6){MapController.of(context).move(pts.first,clusterUntilZoom);return;}
        MapController.of(context).fitCamera(CameraFit.bounds(bounds:b,padding:const EdgeInsets.all(60),maxZoom:clusterUntilZoom));
      },child:Container(alignment:Alignment.center,decoration:BoxDecoration(color:s.surface,shape:BoxShape.circle,
        border:Border.all(color:Color(poiColor(g.first)),width:3),boxShadow:const [BoxShadow(blurRadius:3,color:Colors.black38)]),
        child:Text('${g.length}',style:TextStyle(fontWeight:FontWeight.w800,color:s.onSurface))))));
  }
}

/// The list of the points, with its search, sort and filters.
class PoiListView extends StatefulWidget {
  final List<SarcadePoi> pois; final LatLng? from; final ValueChanged<SarcadePoi> onOpen; final VoidCallback? onClose;
  const PoiListView({super.key,required this.pois,required this.onOpen,this.from,this.onClose});
  @override State<PoiListView> createState()=>_PoiListViewState();
}

class _PoiListViewState extends State<PoiListView> {
  String _query=''; String? _icon, _author; PoiSort _sort=PoiSort.date;
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final authors={for(final p in widget.pois)p.createdBy??''}.toList()..sort();
    final icons={for(final p in widget.pois)p.icon??'pin'};
    final list=filterPois(widget.pois,query:_query,icon:_icon,author:_author,sort:_sort,from:widget.from);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,4,0),child:Row(children:[
        Expanded(child:Text('${S.t('poi.layer')} (${widget.pois.length})',style:t.textTheme.titleMedium)),
        if(widget.onClose!=null)IconButton(tooltip:S.t('common.close'),onPressed:widget.onClose,icon:const Icon(Icons.close)),
      ])),
      Padding(padding:const EdgeInsets.fromLTRB(12,4,12,4),child:TextField(key:const ValueKey('poi-search'),
        decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:S.t('poi.search'),isDense:true,border:const OutlineInputBorder()),
        onChanged:(v)=>setState(()=>_query=v))),
      SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),child:Row(children:[
        for(final s in PoiSort.values)if(s!=PoiSort.distance||widget.from!=null)Padding(padding:const EdgeInsets.only(right:6),
          child:ChoiceChip(label:Text(S.t('poi.sort.${s.name}')),selected:_sort==s,onSelected:(_)=>setState(()=>_sort=s))),
        const SizedBox(width:6),
        PopupMenuButton<String>(tooltip:S.t('poi.filterIcon'),onSelected:(v)=>setState(()=>_icon=v.isEmpty?null:v),
          itemBuilder:(_)=>[PopupMenuItem(value:'',child:Text(S.t('poi.all'))),
            for(final k in poiIcons)if(icons.contains(k))PopupMenuItem(value:k,child:Row(children:[Icon(poiIconData(k),size:18),const SizedBox(width:8),Text(poiIconLabel(k))]))],
          child:Chip(avatar:Icon(_icon==null?Icons.category_outlined:poiIconData(_icon),size:18),label:Text(_icon==null?S.t('poi.filterIcon'):poiIconLabel(_icon)))),
        const SizedBox(width:6),
        PopupMenuButton<String>(tooltip:S.t('poi.filterAuthor'),onSelected:(v)=>setState(()=>_author=v=='*'?null:v),
          itemBuilder:(_)=>[PopupMenuItem(value:'*',child:Text(S.t('poi.all'))),
            for(final a in authors)PopupMenuItem(value:a,child:Text(a.isEmpty?S.t('poi.unknownAuthor'):a))],
          child:Chip(avatar:const Icon(Icons.person_outline,size:18),label:Text(_author==null?S.t('poi.filterAuthor'):_author!.isEmpty?S.t('poi.unknownAuthor'):_author!))),
      ])),
      const Divider(height:12),
      Expanded(child:list.isEmpty?Padding(padding:const EdgeInsets.all(16),child:Text(S.t('poi.none'))):ListView.builder(itemCount:list.length,itemBuilder:(c,i){
        final p=list[i]; final from=widget.from;
        return ListTile(dense:true,key:ValueKey('poi-row-${p.id}'),leading:SizedBox(width:36,child:Center(child:poiSymbol(p,size:30))),
          title:Text(poiName(p),maxLines:1,overflow:TextOverflow.ellipsis),
          subtitle:Text([p.createdBy??S.t('poi.unknownAuthor'),poiTime(p.createdAt),if(from!=null)formatDistance(distanceM(from,LatLng(p.lat,p.lon)))].join(' · ')),
          onTap:()=>widget.onOpen(p));
      })),
    ]);
  }
}
