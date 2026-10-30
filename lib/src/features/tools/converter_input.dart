/// Guided input of the converter (lot 5): one field per part of the
/// format, to note a position given on the radio (degrees / minutes /
/// seconds, zone / square / easting / northing…), built into a text the
/// common parser understands. History of the last conversions. Pure parts
/// are tested.
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../measure/coordinates.dart';

const guidedFormats=[CoordFormat.dd,CoordFormat.dm,CoordFormat.dms,CoordFormat.utm,CoordFormat.mgrs,CoordFormat.qth,CoordFormat.l93,CoordFormat.dfci];

/// Keys of the fields of a format, in order (label: « converter.f.<key> »).
List<String> guidedFieldsOf(CoordFormat f)=>switch(f){
  CoordFormat.dd=>['lat','ns','lon','eo'],
  CoordFormat.dm=>['latD','latM','ns','lonD','lonM','eo'],
  CoordFormat.dms=>['latD','latM','latS','ns','lonD','lonM','lonS','eo'],
  CoordFormat.utm=>['zone','band','e','n'],
  CoordFormat.mgrs=>['gzd','square','e','n'],
  CoordFormat.qth=>['qth'],
  CoordFormat.l93=>['x','y'],
  CoordFormat.dfci=>['dfci'],
};

/// Text understood by parseCoordinates from the fields of [f].
String guidedText(CoordFormat f,Map<String,String> v){
  String g(String k)=>(v[k]??'').trim();
  String h(String k,String d)=>g(k).isEmpty?d:g(k).toUpperCase();
  return switch(f){
    CoordFormat.dd=>'${g('lat')} ${h('ns','N')} ${g('lon')} ${h('eo','E')}',
    CoordFormat.dm=>"${g('latD')}°${g('latM')}' ${h('ns','N')} ${g('lonD')}°${g('lonM')}' ${h('eo','E')}",
    CoordFormat.dms=>"${g('latD')}°${g('latM')}'${g('latS')}\" ${h('ns','N')} ${g('lonD')}°${g('lonM')}'${g('lonS')}\" ${h('eo','E')}",
    CoordFormat.utm=>'${g('zone')}${h('band','')} ${g('e')} ${g('n')}',
    CoordFormat.mgrs=>'${g('gzd').toUpperCase()} ${g('square').toUpperCase()} ${g('e')} ${g('n')}',
    CoordFormat.qth=>g('qth'),
    CoordFormat.l93=>'X ${g('x')} Y ${g('y')}',
    CoordFormat.dfci=>g('dfci'),
  };
}

/// Last 10 conversions, the newest first, without duplicates (~1 m).
List<Map<String,dynamic>> pushHistory(List<Map<String,dynamic>> list,LatLng p,String label,{int max=10}){
  String key(num lat,num lon)=>'${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
  final k=key(p.latitude,p.longitude);
  return [{'lat':p.latitude,'lon':p.longitude,'label':label},
    ...list.where((e)=>key(e['lat'] as num,e['lon'] as num)!=k)].take(max).toList();
}

class GuidedFields extends StatefulWidget {
  final CoordFormat format; final ValueChanged<String> onText;
  const GuidedFields({super.key,required this.format,required this.onText});
  @override State<GuidedFields> createState()=>_GuidedFieldsState();
}

class _GuidedFieldsState extends State<GuidedFields> {
  final Map<String,TextEditingController> _c={};
  @override void dispose(){for(final c in _c.values){c.dispose();}super.dispose();}
  TextEditingController _ctrl(String k)=>_c.putIfAbsent(k,()=>TextEditingController());

  void _changed()=>widget.onText(guidedText(widget.format,{for(final e in _c.entries)e.key:e.value.text}));

  @override Widget build(BuildContext context){
    final fields=guidedFieldsOf(widget.format);
    bool narrow(String k)=>k=='ns'||k=='eo'||k=='band'||k.endsWith('D')||k=='zone'||k=='gzd';
    return Wrap(spacing:8,runSpacing:8,children:[
      for(final f in fields)SizedBox(width:narrow(f)?76:(fields.length<=2?260:110),child:TextField(
        key:ValueKey('guided-$f'),controller:_ctrl(f),onChanged:(_)=>_changed(),
        textCapitalization:TextCapitalization.characters,
        keyboardType:const {'ns','eo','band','square','qth','dfci','gzd'}.contains(f)?TextInputType.text:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:S.t('converter.f.$f'),isDense:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(10))))),
      Text(S.t('converter.fieldsHelp'),style:Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
