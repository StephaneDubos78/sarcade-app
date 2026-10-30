/// One line of the « Affichage » tab (card « Panneau des couches, opacité
/// incohérente », validated on 30 Oct 2026, 1 h 20): name, then the
/// opacity of this layer only while it is shown, then the switch; same
/// layout for every layer. A filter (« Sans Internet seulement ») has no
/// slider.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Opacity keys, one per layer; the first value of a new key is taken from
/// the former group (PR #92: ops, draw, brg, ref).
const layerOpacityLegacy={'ops':'ops','aprs':'ops','poi':'ops','draw':'draw','brg':'brg','high':'ref','relay':'ref'};

/// Opacity of [key] from the stored preferences (`opacity:<key>`), 10 to 100 %.
double layerOpacityFrom(String? Function(String key) read,String key){
  final v=read('opacity:$key')??read('opacity:${layerOpacityLegacy[key]??key}');
  return double.tryParse(v??'')?.clamp(0.1,1.0)??1.0;
}

class LayerRow extends StatelessWidget {
  final String label; final bool on; final ValueChanged<bool> onShown;
  final double? opacity; final ValueChanged<double>? onOpacity;
  /// Optional action after the name (« Voir la liste » of the points).
  final Widget? trailing;
  const LayerRow({super.key,required this.label,required this.on,required this.onShown,this.opacity,this.onOpacity,this.trailing});
  @override Widget build(BuildContext context){
    final t=Theme.of(context); final o=opacity;
    // Narrow (revue d'ergonomie n° 28): the action (« Voir la liste ») goes
    // on a second line under the name, so the name is never squeezed out.
    final narrow=trailing!=null&&layerRowStacksAction(MediaQuery.sizeOf(context).width);
    final main=Padding(padding:const EdgeInsets.only(left:16,right:8),child:SizedBox(height:48,child:Row(children:[
      Expanded(child:Text(label,overflow:TextOverflow.ellipsis,style:t.textTheme.bodyLarge)),
      if(!narrow)?trailing,
      if(on&&o!=null&&onOpacity!=null)...[
        Tooltip(message:S.t('layers.opacity'),child:Icon(Icons.opacity,size:16,color:t.colorScheme.onSurfaceVariant)),
        SizedBox(width:110,child:Slider(value:o,min:0.1,max:1,divisions:9,label:'${(o*100).round()} %',onChanged:onOpacity)),
        SizedBox(width:40,child:Text('${(o*100).round()} %',textAlign:TextAlign.end,style:t.textTheme.bodySmall)),
        const SizedBox(width:4),
      ],
      Switch(value:on,onChanged:onShown),
    ])));
    if(!narrow)return main;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
      main,
      Padding(padding:const EdgeInsets.only(left:16,bottom:4),child:Align(alignment:Alignment.centerLeft,child:trailing)),
    ]);
  }
}

/// Phone width: the action of a layer row goes under its name.
bool layerRowStacksAction(double screenWidth)=>screenWidth<600;

/// Title of a section, same style as the tab titles (card « Panneau Fond de
/// carte, titres de sections », 1 h 34), with a clear separator above.
Widget layerSectionTitle(BuildContext c,String text,{bool first=false})=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
  if(!first)const Divider(height:24),
  Padding(padding:EdgeInsets.fromLTRB(16,first?12:0,16,4),child:Text(text,style:Theme.of(c).textTheme.titleMedium)),
]);
