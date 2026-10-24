import '../../l10n/strings.dart';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../services/sarcade_api.dart';

class LogbookPage extends StatefulWidget {
 final SarcadeApi api; final String eventId;
 const LogbookPage({super.key,required this.api,required this.eventId});
 @override State<LogbookPage> createState()=>_LogbookPageState();
}
class _LogbookPageState extends State<LogbookPage>{
 List<LogbookEntry> entries=[]; bool loading=true;
 @override void initState(){super.initState();_load();}
 Future<void> _load() async {try{entries=await widget.api.logbook(widget.eventId);}finally{if(mounted)setState(()=>loading=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(S.t('map.logbook')),actions:[IconButton(tooltip:S.t('routes.refresh'),onPressed:(){setState(()=>loading=true);_load();},icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):ListView.builder(itemCount:entries.length,itemBuilder:(c,i){final e=entries[i];return ListTile(leading:Icon(e.kind=='ack'?Icons.check_circle_outline:Icons.chat_bubble_outline),title:Text(e.summary),subtitle:Text('${e.time.toLocal()} · ${e.actorId??'-'}'));}));
}
