import '../../l10n/strings.dart';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../services/sarcade_api.dart';
import '../../ui/link_status.dart';

class LogbookPage extends StatefulWidget {
 final SarcadeApi api; final String eventId;
 const LogbookPage({super.key,required this.api,required this.eventId});
 @override State<LogbookPage> createState()=>_LogbookPageState();
}
class _LogbookPageState extends State<LogbookPage>{
 List<LogbookEntry> entries=[]; bool loading=true;
 @override void initState(){super.initState();_load();}
 Future<void> _load() async {try{entries=await widget.api.logbook(widget.eventId);}finally{if(mounted)setState(()=>loading=false);}}
 /// Icon of the kind of entry (message, acknowledgement, bearing, drawing,
 /// access…).
 static IconData kindIcon(String kind)=>switch(kind){
   'ack'=>Icons.check_circle_outline,'message'=>Icons.chat_bubble_outline,
   'map_feature'||'drawing'=>Icons.draw_outlined,'bearing'=>Icons.track_changes,
   'access'||'security'=>Icons.lock_outline,'position'=>Icons.place_outlined,
   _=>Icons.receipt_long_outlined};

 static String _two(int v)=>v.toString().padLeft(2,'0');

 @override Widget build(BuildContext context)=>Scaffold(
   appBar:LinkedAppBar(title:Text(S.t('map.logbook')),actions:[IconButton(tooltip:S.t('routes.refresh'),onPressed:(){setState(()=>loading=true);_load();},icon:const Icon(Icons.refresh))]),
   body:loading?const Center(child:CircularProgressIndicator()):LayoutBuilder(builder:(context,c){
     final wide=c.maxWidth>=700;
     final t=Theme.of(context);
     return ListView.builder(itemCount:entries.length,itemBuilder:(ctx,i){
       final e=entries[i]; final l=e.time.toLocal();
       final hms='${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
       if(!wide){
         return ListTile(leading:Icon(kindIcon(e.kind)),title:Text(e.summary),subtitle:Text('${_two(l.day)}/${_two(l.month)} $hms · ${e.actorId??'-'}'));
       }
       // Wide screen (« Main courante, écran large »): one line per entry,
       // the date only when the day changes.
       final prev=i==0?null:entries[i-1].time.toLocal();
       final newDay=prev==null||prev.day!=l.day||prev.month!=l.month||prev.year!=l.year;
       final row=Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:6),child:Row(children:[
         SizedBox(width:80,child:Text(hms,style:const TextStyle(fontFeatures:[FontFeature.tabularFigures()]))),
         SizedBox(width:140,child:Text(e.actorId??'-',overflow:TextOverflow.ellipsis,style:TextStyle(color:t.colorScheme.onSurfaceVariant))),
         SizedBox(width:32,child:Icon(kindIcon(e.kind),size:18,color:t.colorScheme.onSurfaceVariant)),
         Expanded(child:Text(e.summary,maxLines:1,overflow:TextOverflow.ellipsis)),
       ]));
       if(!newDay)return row;
       return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
         Padding(padding:const EdgeInsets.fromLTRB(16,12,16,4),child:Text('${_two(l.day)}/${_two(l.month)}/${l.year}',style:t.textTheme.labelLarge)),
         row,
       ]);
     });
   }));
}
