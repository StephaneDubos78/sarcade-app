/// State of the link with the server on every screen, top right (card « État
/// de connexion au serveur sur tous les écrans », validated 31 Oct 2026):
/// the coloured dot alone when everything goes well (« Connecté » in its
/// tooltip), the dot and « Ralentie » or « Coupée » otherwise, with the
/// number of items waiting to be sent (« ● Coupée · 3 »). A touch opens
/// Paramètres › Diagnostic. The map keeps its own pill (link + weather).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../features/map/stations.dart' show ServerLink, serverLink;
import '../l10n/strings.dart';
import '../offline/sync_service.dart';
import '../services/realtime_service.dart';

/// Opens Paramètres › Diagnostic; set by the map page while it is open.
VoidCallback? linkStatusOnTap;

/// Colour of the dot, the same rule as on the map.
Color linkColor(ServerLink? s,ColorScheme scheme)=>switch(s){
  ServerLink.direct=>const Color(0xFF2E9D4B),ServerLink.slowed=>Colors.orange,ServerLink.cut=>scheme.error,null=>scheme.outline};

/// Text after the dot: nothing when connected and nothing waits.
String linkText(ServerLink? s,int pending){
  final word=s==ServerLink.slowed||s==ServerLink.cut?S.t('links.${s!.name}'):'';
  if(pending<=0)return word;
  return word.isEmpty?'$pending':'$word · $pending';
}

class LinkStatusPill extends StatefulWidget {
  const LinkStatusPill({super.key});
  @override State<LinkStatusPill> createState()=>_LinkStatusPillState();
}

class _LinkStatusPillState extends State<LinkStatusPill> {
  Timer? _tick;
  @override void initState(){super.initState();_tick=Timer.periodic(const Duration(seconds:3),(_){if(mounted)setState((){});});}
  @override void dispose(){_tick?.cancel();super.dispose();}

  @override Widget build(BuildContext context){
    final sync=OfflineSyncService.active, rt=RealtimeService.active;
    if(sync==null)return const SizedBox.shrink();
    final state=serverLink(syncOk:sync.lastSyncOk,realtime:rt?.connected??false);
    final pending=sync.currentItems.length;
    final scheme=Theme.of(context).colorScheme;
    final text=linkText(state,pending);
    return Tooltip(message:'${S.t('links.serverLink')} : ${S.t('links.${state.name}')}',child:InkWell(key:const ValueKey('link-status'),
      customBorder:const StadiumBorder(),onTap:linkStatusOnTap,
      child:ConstrainedBox(constraints:const BoxConstraints(minWidth:48,minHeight:48),child:Center(child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:10),child:Row(mainAxisSize:MainAxisSize.min,children:[
          Container(width:10,height:10,decoration:BoxDecoration(color:linkColor(state,scheme),shape:BoxShape.circle)),
          if(text.isNotEmpty)...[const SizedBox(width:6),Text(text,style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:scheme.onSurface))],
        ]))))));
  }
}

/// AppBar with the link pill at the end of its actions.
class LinkedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title, leading; final List<Widget>? actions; final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom; final Color? backgroundColor, surfaceTintColor; final double? scrolledUnderElevation, titleSpacing;
  /// False on the first setup (no server yet).
  final bool linkStatus;
  const LinkedAppBar({super.key,this.title,this.leading,this.actions,this.automaticallyImplyLeading=true,this.bottom,
    this.backgroundColor,this.surfaceTintColor,this.scrolledUnderElevation,this.titleSpacing,this.linkStatus=true});
  @override Size get preferredSize=>Size.fromHeight(kToolbarHeight+(bottom?.preferredSize.height??0));
  @override Widget build(BuildContext context)=>AppBar(title:title,leading:leading,automaticallyImplyLeading:automaticallyImplyLeading,bottom:bottom,
    backgroundColor:backgroundColor,surfaceTintColor:surfaceTintColor,scrolledUnderElevation:scrolledUnderElevation,titleSpacing:titleSpacing,
    actions:[...?actions,if(linkStatus)const LinkStatusPill(),const SizedBox(width:4)]);
}
