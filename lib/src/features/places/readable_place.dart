import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';

/// Readable location (decision of 29 Oct 2026, option A): « 800 m au nord de
/// Plaisir », computed by the server from its embedded list of communes,
/// and the nearest road when the server is online.

/// Text of the server answer in the language of the application: commune
/// line, then the road (« 800 m au nord de Plaisir · Rue de la Gare »);
/// null when the server gave nothing usable.
String? placeText(Map<String,dynamic>? d,{bool withRoad=true}){
  if(d==null)return null;
  final label=(S.lang=='fr'?d['label']:(d['label_en']??d['label'])) as String?;
  final road=d['road'] is Map?(d['road'] as Map)['name'] as String?:null;
  final parts=[if(label!=null&&label.isNotEmpty)label,if(withRoad&&road!=null&&road.isNotEmpty)road];
  return parts.isEmpty?null:parts.join(' · ');
}

/// Asks the server, keeps the answers per point (~10 m) for the session.
class PlaceDescriber {
  final SarcadeApi api;
  PlaceDescriber(this.api);
  final Map<String,Map<String,dynamic>> _cache={};
  String _key(LatLng p)=>'${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';

  /// The server answer, or null (older server, offline, too slow).
  Future<Map<String,dynamic>?> describe(LatLng p,{Duration timeout=const Duration(seconds:4)}) async {
    final k=_key(p);
    final hit=_cache[k];
    if(hit!=null)return hit;
    try{
      final d=await api.describePlace(p.latitude,p.longitude).timeout(timeout);
      _cache[k]=d;
      return d;
    }catch(_){return null;}
  }

  /// « (800 m au nord de Plaisir) » for the distress message, or empty when
  /// the server does not answer within [timeout]: the SOS is never held up.
  Future<String> distressSuffix(LatLng? p,{Duration timeout=const Duration(milliseconds:1500)}) async {
    if(p==null)return '';
    final t=placeText(await describe(p,timeout:timeout),withRoad:false);
    return t==null?'':' ($t)';
  }
}

/// One line under a position: readable location, copied with the
/// coordinates on a tap. Nothing shown while unknown.
class PlaceLine extends StatefulWidget {
  final PlaceDescriber describer; final LatLng point;
  const PlaceLine({super.key,required this.describer,required this.point});
  @override State<PlaceLine> createState()=>_PlaceLineState();
}

class _PlaceLineState extends State<PlaceLine> {
  late Future<Map<String,dynamic>?> _f;
  @override void initState(){super.initState();_f=widget.describer.describe(widget.point);}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>?>(future:_f,builder:(c,s){
    final text=placeText(s.data);
    if(text==null)return const SizedBox.shrink();
    final coords='${widget.point.latitude.toStringAsFixed(5)}, ${widget.point.longitude.toStringAsFixed(5)}';
    return InkWell(key:const ValueKey('place-line'),borderRadius:BorderRadius.circular(6),
      onTap:(){
        unawaited(Clipboard.setData(ClipboardData(text:'$coords ($text)')));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
      },
      child:Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[
        Icon(Icons.location_city_outlined,size:16,color:Theme.of(c).colorScheme.onSurfaceVariant),const SizedBox(width:6),
        Expanded(child:SelectableText(text,style:Theme.of(c).textTheme.bodyMedium)),
        Tooltip(message:S.t('common.copy'),child:Icon(Icons.copy,size:14,color:Theme.of(c).colorScheme.onSurfaceVariant)),
      ])));
  });
}
