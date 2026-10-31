import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' show distanceM;
import '../navigation/point_label.dart';

/// Move order of the PCO to an operator (decision of the porteur of
/// 29 October 2026): go to a point of the map. The server checks that only
/// the PCO gives an order and that the operator only answers it.
class MoveOrder {
  final Map<String,dynamic> json;
  const MoveOrder(this.json);
  String get id=>json['id'] as String;
  String get targetId=>'${json['target_id']??''}';
  String get createdBy=>'${json['created_by']??''}';
  String get status=>'${json['status']??'sent'}';
  String get note=>'${json['note']??''}';
  Map<String,dynamic> get _d=>Map<String,dynamic>.from(json['destination'] as Map? ?? const {});
  LatLng get destination=>LatLng((_d['lat'] as num?)?.toDouble()??0,(_d['lon'] as num?)?.toDouble()??0);
  String get label=>pointLabel('${_d['label']??''}');
  /// Still to carry out: sent or accepted.
  bool get open=>status=='sent'||status=='accepted';
  DateTime? get updatedAt=>DateTime.tryParse('${json['updated_at']??''}');
}

/// An order arrived or refused leaves the map on its own after 30 min
/// (card « drapeau vert impossible à retirer », 30 Oct 2026, 1 h 19); it
/// stays in the logbook.
const moveOrderShownAfterAnswer=Duration(minutes:30);
bool moveOrderOnMap(MoveOrder o,DateTime now){
  if(o.status=='cancelled')return false;
  if(o.open)return true;
  final t=o.updatedAt;
  return t==null||now.toUtc().difference(t.toUtc())<moveOrderShownAfterAnswer;
}

/// « Retirer de la carte »: the PCO or the author, at any time.
bool canRemoveMoveOrder(MoveOrder o,String actor,{required bool pco})=>pco||o.createdBy==actor;

/// Distance under which the operator is « arrivé » on his own.
const moveOrderArrivalM=50.0;

bool moveOrderReached(MoveOrder o,LatLng me)=>o.status=='accepted'&&distanceM(me,o.destination)<=moveOrderArrivalM;

Color moveOrderColor(String status)=>switch(status){
  'accepted'=>Colors.blue.shade700,'arrived'=>Colors.green.shade700,'refused'=>Colors.red.shade700,
  'cancelled'=>Colors.grey,_=>Colors.deepOrange,
};

/// PCO view: a dashed line from the operator to the destination and a flag
/// coloured by the answer, for the open orders and the recent answers.
List<Widget> buildMoveOrderLayers(List<MoveOrder> orders,LatLng? Function(String deviceId) positionOf,void Function(MoveOrder) onTap,{DateTime? now}){
  final at=now??DateTime.now();
  final shown=orders.where((o)=>moveOrderOnMap(o,at)).toList();
  if(shown.isEmpty)return const [];
  final lines=<Polyline>[];
  for(final o in shown.where((o)=>o.open)){
    final from=positionOf(o.targetId);
    if(from!=null){
      lines.add(Polyline(points:[from,o.destination],color:moveOrderColor(o.status),strokeWidth:3,
        pattern:StrokePattern.dashed(segments:const [10,8])));
    }
  }
  return [
    if(lines.isNotEmpty)PolylineLayer(polylines:lines),
    MarkerLayer(markers:[for(final o in shown)Marker(point:o.destination,width:44,height:44,alignment:Alignment.topCenter,
      child:GestureDetector(onTap:()=>onTap(o),child:Tooltip(message:'${o.targetId} · ${S.t('order.status.${o.status}')}',
        child:Icon(Icons.flag,size:40,color:moveOrderColor(o.status),shadows:const [Shadow(color:Colors.white,blurRadius:4)]))))]),
  ];
}

/// Choice of the operators and the instruction, by the PCO.
class MoveOrderDraft {
  final List<String> targets; final String label, note;
  const MoveOrderDraft(this.targets,this.label,this.note);
}

Future<MoveOrderDraft?> showMoveOrderDialog(BuildContext context,List<({String id,String label,String? age})> operators){
  final chosen=<String>{};
  final label=TextEditingController(), note=TextEditingController();
  return showDialog<MoveOrderDraft>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
    title:Text(S.t('order.send')),
    content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(controller:label,decoration:InputDecoration(labelText:S.t('order.label'),hintText:S.t('order.point'))),
      TextField(controller:note,maxLength:200,decoration:InputDecoration(labelText:S.t('order.note'))),
      Padding(padding:const EdgeInsets.only(top:8,bottom:4),child:Text(S.t('order.who'),style:Theme.of(c).textTheme.titleSmall)),
      if(operators.isEmpty)Text(S.t('operators.none')),
      Flexible(child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final o in operators)CheckboxListTile(dense:true,value:chosen.contains(o.id),title:Text(o.label),subtitle:o.age==null?null:Text(o.age!),
          onChanged:(v)=>set(()=>v==true?chosen.add(o.id):chosen.remove(o.id))),
      ]))),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:chosen.isEmpty?null:()=>Navigator.pop(c,MoveOrderDraft(chosen.toList(),label.text.trim(),note.text.trim())),
        child:Text(S.t('order.sendButton'))),
    ],
  ))).whenComplete((){label.dispose();note.dispose();});
}

/// Operator view: the open order addressed to me, with its answers.
class MoveOrderBanner extends StatelessWidget {
  final MoveOrder order;
  final VoidCallback onAccept, onRefuse, onNavigate, onArrived;
  const MoveOrderBanner({super.key,required this.order,required this.onAccept,required this.onRefuse,required this.onNavigate,required this.onArrived});
  @override Widget build(BuildContext context){
    final sent=order.status=='sent';
    return Material(elevation:4,borderRadius:BorderRadius.circular(14),color:Colors.deepOrange.shade50,
      child:Padding(padding:const EdgeInsets.fromLTRB(12,8,8,4),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Icon(Icons.flag,color:moveOrderColor(order.status)),const SizedBox(width:8),
          Flexible(child:Text(S.t('order.banner',{'who':order.createdBy,'label':order.label}),
            style:const TextStyle(fontWeight:FontWeight.w700,color:Colors.black87))),
        ]),
        if(order.note.isNotEmpty)Padding(padding:const EdgeInsets.only(left:32,top:2),child:Text(order.note,style:const TextStyle(color:Colors.black87))),
        Wrap(spacing:4,children:[
          if(sent)...[
            FilledButton.icon(onPressed:onAccept,icon:const Icon(Icons.check),label:Text(S.t('order.accept'))),
            OutlinedButton(onPressed:onRefuse,child:Text(S.t('order.refuse'))),
          ] else ...[
            FilledButton.icon(onPressed:onNavigate,icon:const Icon(Icons.directions),label:Text(S.t('nav.goHere'))),
            OutlinedButton(onPressed:onArrived,child:Text(S.t('order.arrived'))),
          ],
        ]),
      ])));
  }
}

/// « Ordres » of the « Affichage » tab: in progress, then done.
List<Widget> moveOrderList(BuildContext c,List<MoveOrder> orders,{required ValueChanged<MoveOrder> onOpen,DateTime? now}){
  final at=now??DateTime.now();
  final live=orders.where((o)=>o.status!='cancelled').toList()..sort((a,b)=>'${b.json['updated_at']}'.compareTo('${a.json['updated_at']}'));
  final open=live.where((o)=>o.open).toList(), done=live.where((o)=>!o.open).toList();
  Widget tile(MoveOrder o)=>ListTile(dense:true,visualDensity:VisualDensity.compact,key:ValueKey('order-row-${o.id}'),
    leading:Icon(Icons.flag,color:moveOrderColor(o.status).withValues(alpha:moveOrderOnMap(o,at)?1:0.4)),
    title:Text('${o.targetId} · « ${o.label} »',maxLines:1,overflow:TextOverflow.ellipsis),
    subtitle:Text(S.t('order.status.${o.status}')),onTap:()=>onOpen(o));
  final t=Theme.of(c).textTheme.labelLarge;
  return [
    // Subtitle of the « Ordres » line (revue n° 30).
    if(live.isEmpty)Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Builder(builder:(c)=>Text(S.t('order.none'),
      style:Theme.of(c).textTheme.bodySmall?.copyWith(color:Theme.of(c).colorScheme.onSurfaceVariant)))),
    if(open.isNotEmpty)...[Padding(padding:const EdgeInsets.fromLTRB(16,4,16,0),child:Text('${S.t('order.inProgress')} · ${open.length}',style:t)),...open.map(tile)],
    if(done.isNotEmpty)...[Padding(padding:const EdgeInsets.fromLTRB(16,4,16,0),child:Text('${S.t('order.done')} · ${done.length}',style:t)),...done.map(tile)],
  ];
}
