import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/message.dart';
import '../../offline/sync_service.dart';

class MessagesPage extends StatefulWidget {
 final String eventId,actorId; final OfflineSyncService sync; final List<SarcadeMessage> messages;
 const MessagesPage({super.key,required this.eventId,required this.actorId,required this.sync,required this.messages});
 @override State<MessagesPage> createState()=>_MessagesPageState();
}
class _MessagesPageState extends State<MessagesPage>{
 final _text=TextEditingController(); final _uuid=const Uuid(); String _priority='routine';
 Future<void> _send() async {
   final body=_text.text.trim(); if(body.isEmpty)return;
   final m=SarcadeMessage(id:_uuid.v4(),eventId:widget.eventId,senderId:widget.actorId,recipientIds:const [],priority:_priority,body:body,createdAt:DateTime.now().toUtc());
   await widget.sync.queue(objectId:m.id,objectType:'message',payload:m.toJson());
   setState(()=>widget.messages.add(m)); _text.clear();
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Messages')),body:Column(children:[
   Expanded(child:ListView.builder(itemCount:widget.messages.length,itemBuilder:(c,i){final m=widget.messages[i];return ListTile(leading:Icon(m.priority=='immediate'?Icons.priority_high:Icons.message),title:Text(m.body),subtitle:Text('${m.senderId} · ${m.priority}'));})),
   SafeArea(child:Row(children:[DropdownButton(value:_priority,items:const [DropdownMenuItem(value:'routine',child:Text('Routine')),DropdownMenuItem(value:'urgent',child:Text('Urgent')),DropdownMenuItem(value:'immediate',child:Text('Immédiat'))],onChanged:(v)=>setState(()=>_priority=v!)),Expanded(child:TextField(controller:_text,decoration:const InputDecoration(hintText:'Message court'))),IconButton(onPressed:_send,icon:const Icon(Icons.send))]))
 ]));
}
