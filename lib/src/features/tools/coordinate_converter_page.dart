/// Convertisseur de coordonnées (menu Outils, 29 Oct 2026): a position given
/// on the radio, typed in any format (degrés décimaux, degrés minutes, DMS,
/// UTM, MGRS, locator QTH), shown in every format, then centred on the map
/// or measured from my position.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../measure/coordinates.dart';

class CoordinateConverterPage extends StatefulWidget {
  final LatLng? initial;
  final void Function(LatLng)? onShow, onMeasure;
  const CoordinateConverterPage({super.key,this.initial,this.onShow,this.onMeasure});
  @override State<CoordinateConverterPage> createState()=>_CoordinateConverterPageState();
}

class _CoordinateConverterPageState extends State<CoordinateConverterPage> {
  late final TextEditingController _text=TextEditingController(text:widget.initial==null?'':formatDd(widget.initial!));
  LatLng? get _point=>parseCoordinates(_text.text);

  @override void dispose(){_text.dispose();super.dispose();}

  void _copy(String v){
    Clipboard.setData(ClipboardData(text:v));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
  }

  void _act(void Function(LatLng)? f){
    final p=_point; if(p==null||f==null)return;
    final nav=Navigator.of(context);
    if(nav.canPop())nav.pop();
    f(p);
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context); final p=_point;
    return Scaffold(
      appBar:AppBar(title:Text(S.t('converter.title'))),
      body:ListView(padding:const EdgeInsets.fromLTRB(20,8,20,24),children:[
        Text(S.t('converter.help'),style:t.textTheme.bodyMedium?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        const SizedBox(height:12),
        TextField(controller:_text,autofocus:widget.initial==null,onChanged:(_)=>setState((){}),
          decoration:InputDecoration(labelText:S.t('converter.input'),hintText:'48°48,074 N 2°08,074 E · 31U DQ 4823 0611',
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),
            suffixIcon:_text.text.isEmpty?null:IconButton(tooltip:S.t('common.close'),onPressed:()=>setState(_text.clear),icon:const Icon(Icons.clear)),
            errorText:_text.text.trim().isNotEmpty&&p==null?S.t('converter.invalid'):null)),
        const SizedBox(height:16),
        if(p!=null)...[
          Card(elevation:0,color:t.colorScheme.surfaceContainerLow,child:Column(children:[
            for(final f in CoordFormat.values)ListTile(
              title:Text(S.t('measure.format.${f.name}'),style:t.textTheme.labelMedium?.copyWith(color:t.colorScheme.onSurfaceVariant)),
              subtitle:SelectableText(formatCoordinates(p,f),style:t.textTheme.titleMedium),
              trailing:IconButton(tooltip:S.t('common.copy'),onPressed:()=>_copy(formatCoordinates(p,f)),icon:const Icon(Icons.copy_outlined))),
          ])),
          const SizedBox(height:16),
          Wrap(spacing:10,runSpacing:10,children:[
            if(widget.onShow!=null)FilledButton.icon(style:FilledButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(widget.onShow),icon:const Icon(Icons.center_focus_strong),label:Text(S.t('converter.show'))),
            if(widget.onMeasure!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(widget.onMeasure),icon:const Icon(Icons.straighten),label:Text(S.t('converter.measure'))),
          ]),
        ],
      ]),
    );
  }
}
