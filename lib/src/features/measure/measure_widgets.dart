import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/strings.dart';
import '../routes/route_models.dart' show formatDistance;
import 'coordinates.dart';
import 'measure_controller.dart';

/// Line from the origin to the designated point, with its label.
List<Widget> buildMeasureLayers(MeasureController m,CoordFormat format){
  final o=m.origin, t=m.target;
  if(t==null)return const [];
  final markers=<Marker>[Marker(point:t,width:36,height:36,child:const Icon(Icons.place,color:Colors.deepOrange,size:34))];
  if(o==null)return [MarkerLayer(markers:markers)];
  final mid=LatLng((o.point.latitude+t.latitude)/2,(o.point.longitude+t.longitude)/2);
  markers.add(Marker(point:mid,width:150,height:28,child:Container(
    alignment:Alignment.center,
    decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.9),borderRadius:BorderRadius.circular(6),boxShadow:const [BoxShadow(blurRadius:2)]),
    child:Text('${formatDistance(m.distanceM??0)} · ${m.trueAzimuth?.round()}°',style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:m.originStale?Colors.grey:Colors.black)),
  )));
  return [
    PolylineLayer(polylines:[Polyline(points:[o.point,t],strokeWidth:3,color:m.originStale?Colors.grey:Colors.deepOrange,pattern:StrokePattern.dashed(segments:const [10,6]))]),
    MarkerLayer(markers:markers),
  ];
}

/// Card of the measure: distance, true and magnetic azimuth, GPS accuracy,
/// coordinates in the three formats, actions.
class MeasureCard extends StatelessWidget {
  final MeasureController m; final CoordFormat format;
  final VoidCallback onSavePoi, onSendMessage, onFit, onOpenElsewhere, onChooseOrigin;
  final ValueChanged<CoordFormat> onFormat;
  const MeasureCard({super.key,required this.m,required this.format,required this.onSavePoi,required this.onSendMessage,
    required this.onFit,required this.onOpenElsewhere,required this.onChooseOrigin,required this.onFormat});

  static bool get _phone=>!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS);

  @override Widget build(BuildContext context){
    final t=m.target;
    if(t==null)return const SizedBox.shrink();
    final theme=Theme.of(context);
    final o=m.origin;
    final arrow=_phone?m.arrowAngle:null;
    String? originNote;
    if(o==null){originNote=S.t('measure.noPosition');}
    else if(m.originStale){originNote=S.t('measure.oldPosition',{'min':m.originAge!.inMinutes});}
    else if(!o.mine){originNote=S.t('measure.from',{'label':o.label});}
    return Card(elevation:4,margin:const EdgeInsets.all(8),child:Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        if(arrow!=null)Transform.rotate(angle:arrow*math.pi/180,child:const Icon(Icons.navigation,size:40,color:Colors.deepOrange))
        else const Icon(Icons.straighten,size:32),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(m.targetLabel,style:theme.textTheme.titleSmall,overflow:TextOverflow.ellipsis),
          if(o!=null)Text('${formatDistance(m.distanceM!)}'
            '${o.accuracyM!=null?' (± ${o.accuracyM!.round()} m)':''}',style:theme.textTheme.titleLarge),
          if(o!=null)Text(S.t('measure.azimuth',{'true':m.trueAzimuth!.round(),'mag':m.magneticAzimuth!.round()})),
          if(originNote!=null)Text(originNote,style:theme.textTheme.bodySmall?.copyWith(color:o==null||m.originStale?theme.colorScheme.error:null)),
        ])),
        PopupMenuButton<String>(tooltip:S.t('map.menu'),onSelected:(v){
          switch(v){
            case 'origin': onChooseOrigin();
            case 'dd': onFormat(CoordFormat.dd);
            case 'dm': onFormat(CoordFormat.dm);
            case 'qth': onFormat(CoordFormat.qth);
          }
        },itemBuilder:(_)=>[
          PopupMenuItem(value:'origin',child:Text(S.t('measure.chooseOrigin'))),
          for(final f in CoordFormat.values)CheckedPopupMenuItem(value:f.name,checked:f==format,child:Text(S.t('measure.format.${f.name}'))),
        ]),
        IconButton(tooltip:S.t('measure.clear'),onPressed:m.clear,icon:const Icon(Icons.close)),
      ]),
      const Divider(),
      for(final f in [format,...CoordFormat.values.where((x)=>x!=format)])Row(children:[
        Expanded(child:Text(formatCoordinates(t,f),style:f==format?theme.textTheme.bodyLarge:theme.textTheme.bodySmall)),
        IconButton(visualDensity:VisualDensity.compact,tooltip:S.t('common.copy'),icon:const Icon(Icons.copy,size:18),onPressed:() async {
          await Clipboard.setData(ClipboardData(text:formatCoordinates(t,f)));
          if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
        }),
      ]),
      Wrap(spacing:6,runSpacing:6,children:[
        ActionChip(avatar:const Icon(Icons.add_location_alt_outlined,size:18),label:Text(S.t('measure.savePoi')),onPressed:onSavePoi),
        ActionChip(avatar:const Icon(Icons.send,size:18),label:Text(S.t('measure.send')),onPressed:onSendMessage),
        ActionChip(avatar:const Icon(Icons.center_focus_strong,size:18),label:Text(S.t('measure.fit')),onPressed:onFit),
        ActionChip(avatar:const Icon(Icons.open_in_new,size:18),label:Text(S.t('ext.open')),onPressed:onOpenElsewhere),
      ]),
    ])));
  }
}

/// Text of the point sent in a message: coordinates, distance and azimuth
/// at the time of sending.
String measureMessage(MeasureController m,CoordFormat format){
  final t=m.target!;
  final lines=['📍 ${m.targetLabel}',formatDd(t),formatDm(t),'QTH ${formatQth(t)}'];
  if(m.origin!=null){
    lines.add(S.t('measure.messageDistance',{'d':formatDistance(m.distanceM!),'true':m.trueAzimuth!.round(),'mag':m.magneticAzimuth!.round()}));
  }
  return lines.join('\n');
}
