import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../routes/route_models.dart';
import 'navigation_controller.dart';

/// Choice of the navigation mode.
Future<String?> chooseNavigationMode(BuildContext context,String label)=>showModalBottomSheet<String>(
  context:context,showDragHandle:true,
  builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(S.t('nav.to',{'label':label}),style:Theme.of(c).textTheme.titleMedium)),
    ListTile(leading:const Icon(Icons.directions_car),title:Text(S.t('nav.mode.car')),onTap:()=>Navigator.pop(c,'car')),
    ListTile(leading:const Icon(Icons.directions_walk),title:Text(S.t('nav.mode.foot')),onTap:()=>Navigator.pop(c,'foot')),
    ListTile(leading:const Icon(Icons.terrain),title:Text(S.t('nav.mode.offroad')),onTap:()=>Navigator.pop(c,'offroad')),
    ListTile(leading:const Icon(Icons.straighten),title:Text(S.t('nav.mode.straight')),subtitle:Text(S.t('nav.mode.straightHelp')),onTap:()=>Navigator.pop(c,'straight')),
  ])),
);

/// Card at the bottom of the map while navigating.
class NavigationCard extends StatelessWidget {
  final NavigationController nav;
  /// Follow mode: map centred on the operator, turned in the direction of travel.
  final bool following;
  final VoidCallback? onRecentre;
  /// Computers: option to turn the map in the direction of travel.
  final bool? rotate;
  final ValueChanged<bool>? onRotate;
  const NavigationCard({super.key,required this.nav,this.following=false,this.onRecentre,this.rotate,this.onRotate});

  String _delta(Itinerary alt,Itinerary main){
    final minutes=((alt.durationS-main.durationS)/60).round();
    return minutes==0?S.t('nav.variant.same'):(minutes>0?'+$minutes min':'$minutes min');
  }

  String _eta(DateTime? t){if(t==null)return '-';final l=t.toLocal();return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';}

  @override Widget build(BuildContext context){
    if(nav.state==NavState.idle&&nav.notice==null)return const SizedBox.shrink();
    final theme=Theme.of(context);
    final it=nav.itinerary;
    final instruction=nav.state==NavState.arrived?S.t('nav.arrived'):(it?.straight??false)?null:nav.nextInstruction;
    return Card(elevation:4,margin:const EdgeInsets.all(8),child:Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        if(it?.straight??false)Transform.rotate(angle:(nav.bearing??0)*math.pi/180,child:const Icon(Icons.navigation,size:32))
        else Icon(nav.state==NavState.arrived?Icons.flag:Icons.directions,size:32),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(S.t('nav.to',{'label':nav.label}),style:theme.textTheme.titleSmall,overflow:TextOverflow.ellipsis),
          if(nav.state==NavState.computing)Text(S.t('nav.computing'))
          else if(nav.state!=NavState.idle)Text('${formatDistance(nav.remaining)} · ${S.t('nav.eta',{'time':_eta(nav.eta)})}'
            '${(it?.straight??false)&&nav.bearing!=null?' · ${nav.bearing!.round()}°':''}'),
        ])),
        IconButton(tooltip:S.t('nav.stop'),onPressed:nav.cancel,icon:const Icon(Icons.close)),
      ]),
      if(instruction!=null)Padding(padding:const EdgeInsets.only(top:6),child:Text(instruction,style:theme.textTheme.bodyLarge)),
      if(it!=null&&nav.alternatives.isNotEmpty&&nav.state==NavState.active)Padding(padding:const EdgeInsets.only(top:6),child:Wrap(spacing:6,runSpacing:4,children:[
        for(var i=0;i<nav.alternatives.length;i++)ActionChip(
          avatar:const Icon(Icons.alt_route,size:18,color:Colors.blueGrey),
          label:Text(S.t('nav.variant',{'n':i+1,'delta':_delta(nav.alternatives[i],it),'length':formatDistance(nav.alternatives[i].lengthM)})),
          onPressed:()=>nav.chooseAlternative(i)),
      ])),
      if(nav.state==NavState.active&&(onRecentre!=null||onRotate!=null))Padding(padding:const EdgeInsets.only(top:4),child:Wrap(spacing:6,crossAxisAlignment:WrapCrossAlignment.center,children:[
        if(!following&&onRecentre!=null)FilledButton.tonalIcon(onPressed:onRecentre,icon:const Icon(Icons.my_location,size:18),label:Text(S.t('nav.recentre'))),
        if(onRotate!=null&&rotate!=null)FilterChip(selected:rotate!,onSelected:onRotate,avatar:const Icon(Icons.explore,size:18),label:Text(S.t('nav.rotate'))),
      ])),
      if(nav.notice!=null)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('nav.notice.${nav.notice}'),style:theme.textTheme.bodySmall?.copyWith(color:nav.notice=='on_device'?null:theme.colorScheme.error))),
      if(nav.state==NavState.active)Padding(padding:const EdgeInsets.only(top:4),child:Text(S.t('nav.shared'),style:theme.textTheme.bodySmall)),
    ])));
  }
}
