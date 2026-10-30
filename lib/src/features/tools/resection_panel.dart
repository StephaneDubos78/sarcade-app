/// Panel of the résection, beside the map (the map stays visible to touch a
/// known point and to see the sights).
library;

import '../../ui/choice_pills.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../l10n/strings.dart';
import '../../models/reference_site.dart';
import '../map/drawing/geometry.dart' as geo;
import '../measure/coordinates.dart';
import '../measure/measure_controller.dart' show formatDeclination;
import 'resection.dart';

class ResectionPanel extends StatefulWidget {
  final ResectionController controller;
  final List<ReferenceSite> sites;
  final VoidCallback onClose;
  final void Function(int index) onPickOnMap;
  final void Function(LatLng) onFocus, onCreatePoint, onSendPosition, onCopy;
  final bool canCompass;
  const ResectionPanel({super.key,required this.controller,required this.sites,required this.onClose,required this.onPickOnMap,
    required this.onFocus,required this.onCreatePoint,required this.onSendPosition,required this.onCopy,this.canCompass=false});
  @override State<ResectionPanel> createState()=>_ResectionPanelState();
}

class _ResectionPanelState extends State<ResectionPanel> {
  final _az=[TextEditingController(),TextEditingController(),TextEditingController()];
  ResectionController get c=>widget.controller;

  @override void initState(){
    super.initState();
    c.addListener(_changed);
    _syncFields();
    if(widget.canCompass)c.startCompass();
  }
  @override void dispose(){c.removeListener(_changed);c.stopCompass();for(final t in _az){t.dispose();}super.dispose();}
  void _changed(){_syncFields();if(mounted)setState((){});}
  /// Fields follow the controller (compass reading), not while typing.
  void _syncFields(){
    for(var i=0;i<3;i++){
      final v=c.sights[i].azimuth;
      final typed=double.tryParse(_az[i].text.replaceAll(',','.'));
      if(v!=null&&typed!=v)_az[i].text=v.toStringAsFixed(v.truncateToDouble()==v?0:1);
      if(v==null&&_az[i].text.isNotEmpty&&typed!=null)_az[i].clear();
    }
  }

  Future<void> _choosePoint(int i) async {
    final picked=await showModalBottomSheet<Object>(context:context,isScrollControlled:true,showDragHandle:true,
      builder:(_)=>_PointPicker(sites:widget.sites,around:c.around));
    if(!mounted)return;
    if(picked is ReferenceSite){c.setKnown(i,KnownPoint(point:LatLng(picked.lat,picked.lon),label:picked.name,site:picked));}
    else if(picked=='map'){widget.onPickOnMap(i);}
  }

  Widget _sight(int i){
    final t=Theme.of(context); final s=c.sights[i]; final k=s.known;
    return Card(elevation:0,color:t.colorScheme.surfaceContainerLow,margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(12),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          CircleAvatar(radius:12,backgroundColor:t.colorScheme.primary,child:Text('${i+1}',style:TextStyle(fontSize:12,color:t.colorScheme.onPrimary,fontWeight:FontWeight.w700))),
          const SizedBox(width:8),
          // Same outlines for every sight, the required ones marked « * »
          // (revue d'ergonomie n° 56).
          Expanded(child:Text('${S.t(i<2?'resection.sight':'resection.sightOptional',{'n':'${i+1}'})}${i<2?' *':''}',style:t.textTheme.titleSmall)),
          if(k!=null||s.azimuth!=null)IconButton(tooltip:S.t('resection.clear'),visualDensity:VisualDensity.compact,
            onPressed:(){c.setKnown(i,null);c.setAzimuth(i,null);_az[i].clear();},icon:const Icon(Icons.close,size:18)),
        ]),
        const SizedBox(height:8),
        OutlinedButton.icon(style:OutlinedButton.styleFrom(alignment:Alignment.centerLeft,minimumSize:const Size.fromHeight(44),
            shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
          onPressed:()=>_choosePoint(i),
          icon:Icon(k?.site==null?(k==null?Icons.search:Icons.place_outlined):(k!.site!.isHighPoint?Icons.terrain:Icons.cell_tower)),
          label:Text(k?.label??S.t('resection.choosePoint'),overflow:TextOverflow.ellipsis)),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:TextField(controller:_az[i],keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:InputDecoration(isDense:true,labelText:S.t('resection.azimuth'),suffixText:'°',border:OutlineInputBorder(borderRadius:BorderRadius.circular(10)),
              ),
            onChanged:(v){final d=double.tryParse(v.replaceAll(',','.').trim());c.setAzimuth(i,d==null||d<0||d>360?null:d);})),
          if(widget.canCompass)...[
            const SizedBox(width:6),
            IconButton.filledTonal(tooltip:S.t('resection.compass'),onPressed:c.hasCompass?()=>c.takeCompass(i):null,icon:const Icon(Icons.explore_outlined)),
          ],
        ]),
        const SizedBox(height:8),
        ChoicePills<bool>(compact:true,
          choices:[(value:false,label:S.t('resection.true'),icon:null),
            (value:true,label:S.t('resection.magnetic',{'d':formatDeclination(c.declination)}),icon:null)],
          selected:s.magnetic,onSelected:(v)=>c.setMagnetic(i,v)),
      ])));
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    final r=c.result; final angle=c.narrowestAngle;
    return Material(elevation:3,child:SafeArea(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,4,0),child:Row(children:[
        Icon(Icons.my_location,color:t.colorScheme.primary),const SizedBox(width:8),
        Expanded(child:Text(S.t('resection.title'),style:t.textTheme.titleLarge)),
        IconButton(tooltip:S.t('common.close'),onPressed:widget.onClose,icon:const Icon(Icons.close)),
      ])),
      Expanded(child:ListView(padding:const EdgeInsets.fromLTRB(16,4,16,16),children:[
        // Help with a small drawing: from where you are, aim at known points.
        Card(elevation:0,color:t.colorScheme.primaryContainer.withValues(alpha:0.5),margin:const EdgeInsets.only(bottom:12),child:Padding(padding:const EdgeInsets.all(12),
          child:Row(children:[
            SizedBox(width:64,height:56,child:CustomPaint(painter:_SchemaPainter(t.colorScheme.primary,t.colorScheme.error))),
            const SizedBox(width:12),
            Expanded(child:Text(S.t('resection.helpShort'),style:t.textTheme.bodyMedium)),
          ]))),
        for(var i=0;i<3;i++)_sight(i),
        if(angle!=null&&c.poorGeometry)Card(elevation:0,color:const Color(0xFFFFF4E5),margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(10),
          child:Row(children:[const Icon(Icons.warning_amber,color:Color(0xFFE8710A)),const SizedBox(width:8),
            Expanded(child:Text(S.t('resection.poor',{'a':angle.toStringAsFixed(0)}),style:const TextStyle(color:Color(0xFF7A3E00))))]))),
        // Not a greyed button: what is missing, the fields circled above.
        if(c.validSights.length<2)Container(key:const ValueKey('resection-missing'),padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),border:Border.all(color:t.colorScheme.tertiary,width:2)),
          child:Row(children:[Icon(Icons.edit_note,color:t.colorScheme.tertiary),const SizedBox(width:10),
            Expanded(child:Text(resectionMissingText(c.missing),style:t.textTheme.bodyMedium?.copyWith(fontWeight:FontWeight.w600)))]))
        else FilledButton.icon(style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48),shape:const StadiumBorder()),
          onPressed:(){final res=c.compute();if(res?.centre!=null)widget.onFocus(res!.centre!);},
          icon:const Icon(Icons.calculate_outlined),label:Text(S.t('resection.compute'))),
        if(r!=null)...[
          const SizedBox(height:12),
          if(r.centre==null)Text(S.t('resection.none'),style:TextStyle(color:t.colorScheme.error))
          else Card(elevation:0,color:t.colorScheme.surfaceContainerLow,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(S.t('resection.found',{'r':geo.formatDistance(r.radiusM)}),style:t.textTheme.titleSmall),
            const SizedBox(height:4),
            SelectableText(formatDd(r.centre!),style:t.textTheme.bodyLarge),
            const SizedBox(height:10),
            Wrap(spacing:8,runSpacing:8,children:[
              FilledButton.icon(onPressed:()=>widget.onCreatePoint(r.centre!),icon:const Icon(Icons.add_location_alt_outlined),label:Text(S.t('resection.createPoint'))),
              OutlinedButton.icon(onPressed:()=>widget.onSendPosition(r.centre!),icon:const Icon(Icons.send_outlined),label:Text(S.t('resection.send'))),
              OutlinedButton.icon(onPressed:()=>widget.onCopy(r.centre!),icon:const Icon(Icons.copy_outlined),label:Text(S.t('common.copy'))),
            ]),
          ]))),
        ],
      ])),
    ])));
  }
}

/// « Saisir l’azimut des visées 1 et 2 », « Choisir le point connu de la
/// visée 2 », both joined.
String resectionMissingText(({List<int> points,List<int> azimuths}) m){
  String n(List<int> l)=>l.length==1?S.t('resection.one',{'n':'${l.first+1}'}):S.t('resection.both',{'a':'${l.first+1}','b':'${l.last+1}'});
  final parts=[if(m.points.isNotEmpty)S.t('resection.missingPoint',{'s':n(m.points)}),if(m.azimuths.isNotEmpty)S.t('resection.missingAzimuth',{'s':n(m.azimuths)})];
  return [for(var i=0;i<parts.length;i++)i==0?parts[i]:parts[i][0].toLowerCase()+parts[i].substring(1)].join(S.t('resection.and'));
}

/// Two known points (triangles) and the sights crossing where you are.
class _SchemaPainter extends CustomPainter {
  final Color line, me;
  _SchemaPainter(this.line,this.me);
  @override void paint(Canvas canvas,Size size){
    final p=Paint()..color=line..strokeWidth=1.6..style=PaintingStyle.stroke;
    const a=Offset(6,8); final b=Offset(size.width-6,12), you=Offset(size.width*0.45,size.height-8);
    for(final k in [a,b]){
      canvas.drawLine(k,you,p);
      final tri=Path()..moveTo(k.dx,k.dy-6)..lineTo(k.dx-5,k.dy+3)..lineTo(k.dx+5,k.dy+3)..close();
      canvas.drawPath(tri,Paint()..color=line);
    }
    canvas.drawCircle(you,5,Paint()..color=me);
  }
  @override bool shouldRepaint(covariant _SchemaPainter old)=>old.line!=line||old.me!=me;
}

/// Search of a known point: text, kinds, sorted by distance; « Toucher la
/// carte » for any other point.
class _PointPicker extends StatefulWidget {
  final List<ReferenceSite> sites; final LatLng? around;
  const _PointPicker({required this.sites,this.around});
  @override State<_PointPicker> createState()=>_PointPickerState();
}

class _PointPickerState extends State<_PointPicker> {
  String _q=''; bool _high=true, _relay=true;
  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    final list=resectionCandidates(widget.sites,around:widget.around,query:_q,highPoints:_high,relays:_relay);
    return SizedBox(height:MediaQuery.sizeOf(context).height*0.8,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:TextField(autofocus:true,onChanged:(v)=>setState(()=>_q=v),
        decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:S.t('resection.search'),isDense:true,
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(28))))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Wrap(spacing:8,children:[
        FilterChip(label:Text(S.t('refs.highPoints')),selected:_high,onSelected:(v)=>setState(()=>_high=v)),
        FilterChip(label:Text(S.t('refs.relays')),selected:_relay,onSelected:(v)=>setState(()=>_relay=v)),
        ActionChip(avatar:const Icon(Icons.touch_app_outlined,size:18),label:Text(S.t('resection.pickMap')),onPressed:()=>Navigator.pop(context,'map')),
      ])),
      if(widget.around!=null)Padding(padding:const EdgeInsets.fromLTRB(16,6,16,0),child:Text(S.t('resection.sorted'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant))),
      const Divider(),
      Expanded(child:list.isEmpty?Center(child:Text(S.t('resection.noMatch'))):ListView.builder(itemCount:list.length,itemBuilder:(_,i){
        final e=list[i]; final s=e.site;
        return ListTile(
          leading:Icon(s.isHighPoint?Icons.terrain:Icons.cell_tower,color:s.isHighPoint?Colors.indigo:Colors.deepOrange),
          title:Text(s.name,overflow:TextOverflow.ellipsis),
          subtitle:Text([if(s.callsign?.isNotEmpty==true)s.callsign!,if(s.altM!=null)'${s.altM!.toStringAsFixed(0)} m'].join(' · ')),
          trailing:e.distanceM==null?null:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
            Text(geo.formatDistance(e.distanceM!),style:t.textTheme.labelLarge),
            Text('≈ ${e.bearingDeg!.toStringAsFixed(0).padLeft(3,'0')}°',style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
          ]),
          onTap:()=>Navigator.pop(context,s));
      })),
    ]));
  }
}
