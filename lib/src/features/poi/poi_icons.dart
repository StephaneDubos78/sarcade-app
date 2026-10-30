/// Shape of the icon of a point of interest (card « Points d'intérêt,
/// création claire et icônes », validated on 30 Oct 2026, 1 h 13): a
/// simple set of symbols, chosen when the point is created and changed in
/// its sheet; stored on the point (`icon`, server migration 0024). The
/// SDIS / NATO (APP-6) / SATER symbols come later.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// Keys stored on the server, in the order of the panel; `pin` = default.
const poiIcons=['pin','gathering','command_post','danger','parking','water','helipad','vehicle','viewpoint','medical','radio','shelter','flag'];

IconData poiIconData(String? key)=>switch(key){
  'gathering'=>Icons.groups,'command_post'=>Icons.home_work,'danger'=>Icons.warning_amber,'parking'=>Icons.local_parking,
  'water'=>Icons.water_drop,'helipad'=>Icons.flight,'vehicle'=>Icons.directions_car,'viewpoint'=>Icons.visibility,
  'medical'=>Icons.local_hospital,'radio'=>Icons.cell_tower,'shelter'=>Icons.cottage,'flag'=>Icons.flag,_=>Icons.location_on};

String poiIconLabel(String? key)=>S.t('poi.icon.${poiIcons.contains(key)?key:'pin'}');

/// Default name of a new point: « Point HH:MM » (never « Point désigné »).
String defaultPoiName([DateTime? now]){
  final t=(now??DateTime.now()).toLocal(); String two(int v)=>v.toString().padLeft(2,'0');
  return S.t('poi.defaultName',{'hm':'${two(t.hour)}:${two(t.minute)}'});
}

/// Panel of symbols: a grid of round icons with their names.
class PoiIconPanel extends StatelessWidget {
  final String selected; final ValueChanged<String> onPick; final Color color;
  const PoiIconPanel({super.key,required this.selected,required this.onPick,required this.color});
  @override Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Wrap(spacing:4,runSpacing:4,children:[for(final k in poiIcons)SizedBox(width:72,child:InkWell(
      key:ValueKey('poi-icon-$k'),borderRadius:BorderRadius.circular(12),onTap:()=>onPick(k),
      child:Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:40,height:40,decoration:BoxDecoration(shape:BoxShape.circle,
          color:k==selected?s.primaryContainer:s.surfaceContainerHigh,border:Border.all(color:k==selected?s.primary:Colors.transparent,width:2)),
          child:Icon(poiIconData(k),size:22,color:color)),
        const SizedBox(height:2),
        Text(poiIconLabel(k),textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
      ]))))]);
  }
}

/// Small window of creation: name (default « Point HH:MM ») and icon.
/// Returns null when cancelled.
Future<({String name,String icon})?> showCreatePoiDialog(BuildContext context,{required Color color,String? name}){
  final ctl=TextEditingController(text:name??defaultPoiName());
  var icon='pin';
  return showDialog<({String name,String icon})>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set){
    void ok(){final n=ctl.text.trim();Navigator.pop(c,(name:n.isEmpty?defaultPoiName():n,icon:icon));}
    return AlertDialog(title:Text(S.t('poi.createHere')),
      content:SizedBox(width:400,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(key:const ValueKey('poi-create-name'),controller:ctl,autofocus:true,maxLength:160,
          decoration:InputDecoration(labelText:S.t('poi.name')),onSubmitted:(_)=>ok()),
        Padding(padding:const EdgeInsets.only(top:4,bottom:6),child:Text(S.t('poi.iconTitle'),style:Theme.of(c).textTheme.titleSmall)),
        PoiIconPanel(selected:icon,color:color,onPick:(k)=>set(()=>icon=k)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('poi-create-ok'),onPressed:ok,child:Text(S.t('poi.create')))]);
  })).whenComplete(ctl.dispose);
}

/// Change of the icon from the sheet; null when cancelled.
Future<String?> showPoiIconPicker(BuildContext context,{required String current,required Color color})=>
  showModalBottomSheet<String>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>SafeArea(child:Padding(
    padding:const EdgeInsets.fromLTRB(16,0,16,16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(S.t('poi.iconTitle'),style:Theme.of(c).textTheme.titleMedium),const SizedBox(height:8),
      PoiIconPanel(selected:current,color:color,onPick:(k)=>Navigator.pop(c,k)),
    ]))));
