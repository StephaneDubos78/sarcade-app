import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import 'basemap_models.dart';

/// Choice of the base map: layers of the server catalog, the event default
/// chosen by the PCO, and the offline packages served by the local server.
Future<void> showBasemapSheet(BuildContext context,{required List<Basemap> catalog,required Basemap current,
    required String eventDefault,required bool preferOffline,
    required void Function(String id) onChoose,required ValueChanged<bool> onPreferOffline}) {
  var offline=preferOffline;
  return showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set){
    return SafeArea(child:ConstrainedBox(constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(c).height*0.8),child:ListView(shrinkWrap:true,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('basemap.title'),style:Theme.of(c).textTheme.titleLarge)),
      for(final b in catalog)ListTile(
        leading:Icon(b.id==current.id?Icons.radio_button_checked:Icons.radio_button_off),
        title:Text(b.name),
        subtitle:Text([
          if(b.id==eventDefault)S.t('basemap.eventDefault'),
          if(b.hasOfflinePackage)S.t('basemap.offlineAvailable'),
          b.attribution,
        ].join(' · ')),
        onTap:(){onChoose(b.id);Navigator.pop(c);},
      ),
      if(catalog.any((b)=>b.hasOfflinePackage))SwitchListTile(
        value:offline,
        onChanged:(v){onPreferOffline(v);set(()=>offline=v);},
        title:Text(S.t('basemap.preferOffline')),
        subtitle:Text(S.t('basemap.preferOfflineHelp')),
      ),
    ])));
  }));
}
