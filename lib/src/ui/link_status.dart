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
import 'test_ids.dart';
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
    return withId('link.status',Tooltip(message:'${S.t('links.serverLink')} : ${S.t('links.${state.name}')}',child:InkWell(key:const ValueKey('link-status'),
      customBorder:const StadiumBorder(),onTap:linkStatusOnTap,
      child:ConstrainedBox(constraints:const BoxConstraints(minWidth:48,minHeight:48),child:Center(child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:10),child:Row(mainAxisSize:MainAxisSize.min,children:[
          Container(width:10,height:10,decoration:BoxDecoration(color:linkColor(state,scheme),shape:BoxShape.circle)),
          if(text.isNotEmpty)...[const SizedBox(width:6),Text(text,style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:scheme.onSurface))],
        ])))))));
  }
}

/// AppBar with the link pill at the end of its actions.
/// Secondary action of a [LinkedAppBar] (card C3 of the cinématique
/// review, 31 Oct 2026): written out on a wide screen, an icon on a phone,
/// and in the ⋮ menu when there are two or more on a phone, so the title
/// keeps its room next to the link status pill.
class AppBarAction {
  final IconData icon; final String label; final VoidCallback? onPressed; final Key? key;
  /// Written with its label on a wide screen (« Diffuser »), an icon otherwise.
  final bool written;
  const AppBarAction({required this.icon,required this.label,required this.onPressed,this.written=false,this.key});
}

/// Width under which secondary actions shrink (phone in portrait).
const double appBarNarrowWidth=600;

/// How the secondary actions show for a screen width: 'wide', 'icons' or
/// 'menu' (⋮).
String appBarActionsLayout(double width,int n)=>width>=appBarNarrowWidth?'wide':(n>=2?'menu':'icons');

class LinkedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title, leading; final List<Widget>? actions; final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom; final Color? backgroundColor, surfaceTintColor; final double? scrolledUnderElevation, titleSpacing;
  /// Actions that give way to the title on a phone (see [AppBarAction]).
  final List<AppBarAction> secondary;
  /// False on the first setup (no server yet).
  final bool linkStatus;
  const LinkedAppBar({super.key,this.title,this.leading,this.actions,this.automaticallyImplyLeading=true,this.bottom,
    this.backgroundColor,this.surfaceTintColor,this.scrolledUnderElevation,this.titleSpacing,this.linkStatus=true,this.secondary=const []});
  @override Size get preferredSize=>Size.fromHeight(kToolbarHeight+(bottom?.preferredSize.height??0));
  List<Widget> _secondary(BuildContext context){
    if(secondary.isEmpty)return const [];
    switch(appBarActionsLayout(MediaQuery.sizeOf(context).width,secondary.length)){
      case 'wide':return [for(final a in secondary)a.written
        ?TextButton.icon(key:a.key,onPressed:a.onPressed,icon:Icon(a.icon),label:Text(a.label))
        :IconButton(key:a.key,tooltip:a.label,onPressed:a.onPressed,icon:Icon(a.icon))];
      case 'icons':return [for(final a in secondary)IconButton(key:a.key,tooltip:a.label,onPressed:a.onPressed,icon:Icon(a.icon))];
      default:return [PopupMenuButton<int>(key:const ValueKey('appbar-more'),tooltip:S.t('appbar.more'),icon:const Icon(Icons.more_vert),
        onSelected:(i)=>secondary[i].onPressed?.call(),
        itemBuilder:(_)=>[for(var i=0;i<secondary.length;i++)PopupMenuItem<int>(key:secondary[i].key,value:i,enabled:secondary[i].onPressed!=null,
          child:Row(children:[Icon(secondary[i].icon,size:20),const SizedBox(width:12),Flexible(child:Text(secondary[i].label))]))])];
    }
  }
  @override Widget build(BuildContext context)=>AppBar(title:title,leading:leading,automaticallyImplyLeading:automaticallyImplyLeading,bottom:bottom,
    backgroundColor:backgroundColor,surfaceTintColor:surfaceTintColor,scrolledUnderElevation:scrolledUnderElevation,titleSpacing:titleSpacing,
    actions:[...?actions,..._secondary(context),if(linkStatus)const LinkStatusPill(),const SizedBox(width:4)]);
}
