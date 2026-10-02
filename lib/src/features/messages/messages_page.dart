import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/message.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';

class MessagesPage extends StatefulWidget {
 final String eventId,actorId; final OfflineSyncService sync; final LocalStore store;
 const MessagesPage({super.key,required this.eventId,required this.actorId,required this.sync,required this.store});
 @override State<MessagesPage> createState()=>_MessagesPageState();
}
class _MessagesPageState extends State<MessagesPage>{
 final _text=TextEditingController(); final _uuid=const Uuid(); String _priority='routine';
 List<SarcadeMessage> get _messages=>(widget.store.messages().map(SarcadeMessage.fromJson).toList()..sort((a,b)=>a.createdAt.compareTo(b.createdAt)));
 Map<String,List<SarcadeAck>> get _acks {
   final out=<String,List<SarcadeAck>>{};
   for(final j in widget.store.acks()){final a=SarcadeAck.fromJson(j);(out[a.messageId]??=[]).add(a);}
   return out;
 }
 Future<void> _send() async {
   final body=_text.text.trim(); if(body.isEmpty)return;
   final m=SarcadeMessage(id:_uuid.v4(),eventId:widget.eventId,senderId:widget.actorId,recipientIds:const [],priority:_priority,body:body,createdAt:DateTime.now().toUtc());
   await widget.store.cacheMessage(m.toJson());
   await widget.sync.queue(objectId:m.id,objectType:'message',payload:m.toJson());
   if(mounted)setState((){}); _text.clear();
 }
 Future<void> _ack(SarcadeMessage m,String status) async {
   final a=SarcadeAck(id:_uuid.v4(),eventId:widget.eventId,messageId:m.id,actorId:widget.actorId,status:status,time:DateTime.now().toUtc());
   await widget.store.cacheAck(a.toJson());
   await widget.sync.queue(objectId:a.id,objectType:'ack',payload:a.toJson());
   if(mounted)setState((){});
 }
 @override Widget build(BuildContext context){
   final messages=_messages,acks=_acks;
   return Scaffold(appBar:AppBar(title:Text('Messages · ${widget.store.pendingCount()} en attente')),body:Column(children:[
    Expanded(child:ListView.builder(itemCount:messages.length,itemBuilder:(c,i){
      final m=messages[i], mine=m.senderId==widget.actorId, ma=acks[m.id]??[];
      return Card(child:ListTile(
        leading:Icon(m.priority=='immediate'?Icons.priority_high:m.priority=='urgent'?Icons.warning_amber:Icons.message),
        title:Text(m.body),subtitle:Text('${m.senderId} · ${m.priority}\nACK: ${ma.map((a)=>a.status).join(', ')}'),
        trailing:mine?null:PopupMenuButton<String>(onSelected:(s)=>_ack(m,s),itemBuilder:(_)=>const [
          PopupMenuItem(value:'received',child:Text('Reçu')),PopupMenuItem(value:'read',child:Text('Lu')),
          PopupMenuItem(value:'accepted',child:Text('Accepté')),PopupMenuItem(value:'rejected',child:Text('Refusé'))]),
      ));
    })),
    SafeArea(child:Row(children:[
      DropdownButton(value:_priority,items:const [DropdownMenuItem(value:'routine',child:Text('Routine')),DropdownMenuItem(value:'urgent',child:Text('Urgent')),DropdownMenuItem(value:'immediate',child:Text('Immédiat'))],onChanged:(v)=>setState(()=>_priority=v!)),
      Expanded(child:TextField(controller:_text,maxLength:2048,decoration:const InputDecoration(hintText:'Message court',counterText:''))),
      IconButton(onPressed:_send,icon:const Icon(Icons.send))
    ]))
   ]));
 }
}
