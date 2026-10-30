import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import 'basemap_models.dart';

/// One « Fond et affichage » button, two tabs (card « Carte, un seul bouton
/// Fond et affichage », decision of 30 Oct 2026, 3 h 05): « Fond de carte »
/// (one line per base map, the name only, decision of 1 h 34) and
/// « Affichage » (sections Équipes, Opération, Référentiel ADRASEC). The
/// licence notices stay on the map (ⓘ) and in Paramètres › À propos.
Future<void> showBasemapSheet(BuildContext context,{required List<Basemap> catalog,required Basemap current,
    required String eventDefault,required bool preferOffline,
    required void Function(String id) onChoose,required ValueChanged<bool> onPreferOffline,
    List<Widget> Function(BuildContext context,StateSetter refresh)? layers}) {
  var offline=preferOffline;
  // The radio follows the choice while the panel stays open (29 Oct 2026).
  var selected=current.id;
  return showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set){
    final basemaps=ListView(shrinkWrap:true,children:[
      for(final b in catalog)ListTile(
        leading:Icon(b.id==selected?Icons.radio_button_checked:Icons.radio_button_off),
        title:Text(b.name,maxLines:1,overflow:TextOverflow.ellipsis),
        onTap:(){onChoose(b.id);set(()=>selected=b.id);},
      ),
      if(catalog.any((b)=>b.hasOfflinePackage))SwitchListTile(
        value:offline,
        onChanged:(v){onPreferOffline(v);set(()=>offline=v);},
        title:Text(S.t('basemap.preferOffline')),
      ),
    ]);
    final height=MediaQuery.sizeOf(c).height*0.7;
    return SafeArea(child:SizedBox(height:height,child:DefaultTabController(length:layers==null?1:2,child:Column(children:[
      // « Affichage » on the left and open by default, « Fond de carte » on
      // the right (card « Bouton Fond et affichage », 30 Oct 2026, 10 h 31).
      TabBar(tabs:[if(layers!=null)Tab(text:S.t('display.layers')),Tab(text:S.t('basemap.title'))]),
      Expanded(child:TabBarView(children:[if(layers!=null)ListView(children:layers(c,set)),basemaps])),
    ]))));
  }));
}

/// Licence notices of the base maps (OpenStreetMap, OpenTopoMap, IGN), each
/// once, for the ⓘ of the map and Paramètres › À propos.
List<String> basemapNotices(Iterable<Basemap> catalog)=>{
  for(final b in catalog)if(b.attribution.trim().isNotEmpty)b.attribution.trim()}.toList();
