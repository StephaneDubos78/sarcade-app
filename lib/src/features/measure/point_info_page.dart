/// Fiche « Infos du point » (lot 5, validated on the mock-up on 30 Oct
/// 2026, 2 h 00): opened from the location line of the point menu or from
/// « Ma position ». Blocks Coordonnées (decimal, DMS, MGRS, UTM, Maidenhead
/// locator), Lieu (IGN altitude, GPS altitude as fallback for my position;
/// commune and department, readable location, approximate address), Depuis
/// ma position (distance, true and magnetic azimuth), and for my position a
/// GPS block (accuracy, time, course, speed). Every line is copied on a
/// tap; « Copier tout » and « Envoyer en message ». Metric units.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' as geo;
import '../places/readable_place.dart';
import 'coordinate_rows.dart';
import 'coordinates.dart';
import 'wmm.dart';
import '../../ui/link_status.dart';

/// GPS fix of my own position.
class GpsFix {
  final double? accuracyM, altitudeM, headingDeg, speedMps; final DateTime? time;
  const GpsFix({this.accuracyM,this.altitudeM,this.headingDeg,this.speedMps,this.time});
}

String _two(int v)=>v.toString().padLeft(2,'0');
String hms(DateTime t){final l=t.toLocal();return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';}
String _deg(double d)=>'${d.round()%360}°'.padLeft(4,'0');

/// Lines of the sheet, for « Copier tout » and « Envoyer en message »:
/// pure, tested.
List<(String,String)> pointInfoLines({required LatLng point,Map<String,dynamic>? place,GpsFix? gps,LatLng? from,DateTime? now}){
  final out=<(String,String)>[];
  for(final f in infoFormats){out.add((formatLabel(f),formatCoordinates(point,f)));}
  final alt=(place?['altitude_m'] as num?)?.toDouble();
  if(alt!=null){out.add((S.t('info.altitude'),'${alt.round()} m (IGN)'));}
  else if(gps?.altitudeM!=null){out.add((S.t('info.altitude'),'${gps!.altitudeM!.round()} m (GPS)'));}
  final commune=place?['commune'] is Map?(place!['commune'] as Map)['name'] as String?:null;
  if(commune!=null){out.add((S.t('info.commune'),[commune,if(place?['department']!=null)'(${place!['department']})'].join(' ')));}
  final label=placeText(place,withRoad:false);
  if(label!=null)out.add((S.t('info.readable'),label));
  final road=place?['road'] is Map?(place!['road'] as Map)['label'] as String?:null;
  if(road!=null&&road.isNotEmpty)out.add((S.t('info.address'),'≈ $road'));
  if(from!=null&&gps==null){
    final d=geo.distanceM(from,point), az=geo.bearingDeg(from,point);
    final mag=(az-magneticDeclination(from.latitude,from.longitude,now??DateTime.now()))%360;
    out.add((S.t('info.distance'),geo.formatDistance(d)));
    out.add((S.t('info.azimuth'),'${_deg(az)} ${S.t('info.true')} · ${_deg(mag)} ${S.t('info.magnetic')}'));
  }
  if(gps!=null){
    if(gps.accuracyM!=null)out.add((S.t('info.accuracy'),'± ${gps.accuracyM!.round()} m'));
    if(gps.time!=null)out.add((S.t('info.time'),hms(gps.time!)));
    final moving=(gps.speedMps??0)>0.5;
    if(moving&&gps.headingDeg!=null)out.add((S.t('info.course'),_deg(gps.headingDeg!)));
    if(gps.speedMps!=null)out.add((S.t('info.speed'),'${(gps.speedMps!*3.6).toStringAsFixed(moving?0:1).replaceAll('.',',')} km/h'));
  }
  return out;
}

String pointInfoText(String title,List<(String,String)> lines)=>[title,for(final l in lines)'${l.$1} : ${l.$2}'].join('\n');

class PointInfoPage extends StatefulWidget {
  final LatLng point; final String title; final PlaceDescriber places;
  /// My own position: GPS block, no « Depuis ma position ».
  final GpsFix? gps;
  /// My position, for distance and azimuth (null: block hidden).
  final LatLng? from;
  final void Function(String text)? onSendMessage;
  const PointInfoPage({super.key,required this.point,required this.title,required this.places,this.gps,this.from,this.onSendMessage});
  @override State<PointInfoPage> createState()=>_PointInfoPageState();
}

class _PointInfoPageState extends State<PointInfoPage> {
  Map<String,dynamic>? _place; bool _loading=true;

  @override void initState(){
    super.initState();
    widget.places.describe(widget.point).then((d){if(mounted)setState((){_place=d;_loading=false;});});
  }

  List<(String,String)> get _lines=>pointInfoLines(point:widget.point,place:_place,gps:widget.gps,from:widget.from);

  @override Widget build(BuildContext context){
    final lines=_lines; final p=widget.point;
    Iterable<Widget> rows(Iterable<(String,String)> list,IconData icon)=>[for(final l in list)InfoRow(label:l.$1,value:l.$2,icon:icon)];
    final placeKeys={S.t('info.altitude'),S.t('info.commune'),S.t('info.readable'),S.t('info.address')};
    final fromKeys={S.t('info.distance'),S.t('info.azimuth')};
    final gpsKeys={S.t('info.accuracy'),S.t('info.time'),S.t('info.course'),S.t('info.speed')};
    final place=lines.where((l)=>placeKeys.contains(l.$1)).toList();
    final from=lines.where((l)=>fromKeys.contains(l.$1)).toList();
    final gps=lines.where((l)=>gpsKeys.contains(l.$1)).toList();
    return Scaffold(
      appBar:LinkedAppBar(title:Text(widget.title)),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
        InfoBlock(title:S.t('info.coordinates'),children:coordinateRows(p,infoFormats)),
        InfoBlock(title:S.t('info.place'),trailing:_loading?const Padding(padding:EdgeInsets.all(10),child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))):null,
          children:[...rows(place,Icons.place_outlined),
            if(place.isEmpty&&!_loading)Padding(padding:const EdgeInsets.fromLTRB(12,4,12,8),child:Text(S.t('info.placeNone'),style:Theme.of(context).textTheme.bodySmall))]),
        if(from.isNotEmpty)InfoBlock(title:S.t('info.fromMe'),children:[...rows(from,Icons.straighten)]),
        if(gps.isNotEmpty)InfoBlock(title:S.t('info.gps'),children:[...rows(gps,Icons.gps_fixed)]),
        const SizedBox(height:4),
        Wrap(spacing:10,runSpacing:10,children:[
          FilledButton.icon(key:const ValueKey('info-copy-all'),style:FilledButton.styleFrom(shape:const StadiumBorder()),
            onPressed:()=>copyText(context,pointInfoText(widget.title,_lines)),icon:const Icon(Icons.copy_all),label:Text(S.t('info.copyAll'))),
          if(widget.onSendMessage!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
            onPressed:(){final text=pointInfoText(widget.title,_lines);final nav=Navigator.of(context);if(nav.canPop())nav.pop();widget.onSendMessage!(text);},
            icon:const Icon(Icons.send_outlined),label:Text(S.t('info.send'))),
        ]),
      ]),
    );
  }
}
