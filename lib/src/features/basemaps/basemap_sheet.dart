import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import 'basemap_models.dart';

/// Choice of the base map: layers of the server catalog, the event default
/// chosen by the PCO, and the offline packages served by the local server.
Future<void> showBasemapSheet(BuildContext context,{required List<Basemap> catalog,required Basemap current,
    required String eventDefault,required bool preferOffline,
    required void Function(String id) onChoose,required ValueChanged<bool> onPreferOffline,
    List<Widget> Function(BuildContext context,StateSetter refresh)? layers}) {
  var offline=preferOffline;
  // The radio follows the choice while the panel stays open (29 Oct 2026).
  var selected=current.id;
  return showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set){
    return SafeArea(child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(c).height*0.8),child:ListView(shrinkWrap:true,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('basemap.title'),style:Theme.of(c).textTheme.titleLarge)),
      for(final b in catalog)ListTile(
        leading:Icon(b.id==selected?Icons.radio_button_checked:Icons.radio_button_off),
        title:Text(b.name),
        subtitle:Text([
          if(b.id==eventDefault)S.t('basemap.eventDefault'),
          if(b.hasOfflinePackage)S.t('basemap.offlineAvailable'),
          b.attribution,
        ].join(' · ')),
        onTap:(){onChoose(b.id);if(layers==null){Navigator.pop(c);}else{set(()=>selected=b.id);}},
      ),
      if(catalog.any((b)=>b.hasOfflinePackage))SwitchListTile(
        value:offline,
        onChanged:(v){onPreferOffline(v);set(()=>offline=v);},
        title:Text(S.t('basemap.preferOffline')),
        subtitle:Text(S.t('basemap.preferOfflineHelp')),
      ),
      // « Panneau des couches » (28 Oct 2026): what is shown on the map, in
      // the same panel as the base map.
      if(layers!=null)...layers(c,set),
    ])));
  }));
}
