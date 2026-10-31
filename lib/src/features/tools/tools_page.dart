/// Menu « Outils » (validated on 29 Oct 2026, 13 h 14): the tools used less
/// often than the rail entries, as tiles, ordered by use (30 Oct 2026, 12 h 50).
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../ui/link_status.dart';

/// Group of a tool (card « Outils, ordre par usage », 30 Oct 2026, 12 h 50):
/// « Sur le terrain » (Météo, Convertisseur, Itinéraires, Résection), then
/// « Au PC » (Afficher sur une TV, APRS de l'événement).
enum ToolGroup { field, pc }

class ToolItem {
  final IconData icon; final String title, subtitle; final Color color; final VoidCallback onTap; final ToolGroup group;
  const ToolItem({required this.icon,required this.title,required this.subtitle,required this.color,required this.onTap,this.group=ToolGroup.field});
}

class ToolsPage extends StatelessWidget {
  final List<ToolItem> items;
  const ToolsPage({super.key,required this.items});

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('tools.title'))),
      body:LayoutBuilder(builder:(context,c){
        final columns=c.maxWidth>=900?3:c.maxWidth>=560?2:1;
        Widget tile(ToolItem i)=>Card(elevation:0,clipBehavior:Clip.antiAlias,
            color:t.colorScheme.surfaceContainerLow,
            child:InkWell(
              // On a phone the page is a screen of its own: it closes first,
              // so that a tool working on the map shows the map.
              onTap:(){final nav=Navigator.of(context);if(nav.canPop())nav.pop();i.onTap();},
              child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
                Container(width:48,height:48,decoration:BoxDecoration(color:i.color.withValues(alpha:0.14),shape:BoxShape.circle),
                  child:Icon(i.icon,color:i.color)),
                const SizedBox(width:14),
                Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(i.title,style:t.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w600)),
                  const SizedBox(height:2),
                  Text(i.subtitle,maxLines:2,overflow:TextOverflow.ellipsis,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
                ])),
                Icon(Icons.chevron_right,color:t.colorScheme.onSurfaceVariant),
              ]))));
        return CustomScrollView(slivers:[
          for(final g in ToolGroup.values)
            if(items.any((i)=>i.group==g))...[
              SliverPadding(padding:const EdgeInsets.fromLTRB(20,16,16,8),sliver:SliverToBoxAdapter(child:Text(
                S.t(g==ToolGroup.field?'tools.groupField':'tools.groupPc'),
                style:t.textTheme.titleSmall?.copyWith(color:t.colorScheme.primary,fontWeight:FontWeight.w600)))),
              SliverPadding(padding:const EdgeInsets.fromLTRB(16,0,16,8),sliver:SliverGrid.count(
                crossAxisCount:columns,mainAxisSpacing:12,crossAxisSpacing:12,
                childAspectRatio:columns==1?4.2:2.6,
                children:[for(final i in items)if(i.group==g)tile(i)])),
            ],
          const SliverToBoxAdapter(child:SizedBox(height:16)),
        ]);
      }),
    );
  }
}
