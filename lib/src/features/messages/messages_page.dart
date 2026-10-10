import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../models/message.dart';
import '../../models/recipient.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../platform/platform_services.dart';
import '../../services/sarcade_api.dart';
import 'photo_attachment.dart';

class MessagesPage extends StatefulWidget {
 final SarcadeApi api; final String eventId,actorId; final OfflineSyncService sync; final LocalStore store;
 const MessagesPage({super.key,required this.api,required this.eventId,required this.actorId,required this.sync,required this.store});
 @override State<MessagesPage> createState()=>_MessagesPageState();
}
class _MessagesPageState extends State<MessagesPage>{
 final _text=TextEditingController(); final _recipient=TextEditingController(); final _uuid=const Uuid(); String _priority='routine'; String _recipientType='team';
 bool _picking=false;
 List<SarcadeMessage> get _messages=>(widget.store.messages().map(SarcadeMessage.fromJson).toList()..sort((a,b)=>a.createdAt.compareTo(b.createdAt)));
 Map<String,List<SarcadeAck>> get _acks {
   final out=<String,List<SarcadeAck>>{};
   for(final j in widget.store.acks()){final a=SarcadeAck.fromJson(j);(out[a.messageId]??=[]).add(a);}
   return out;
 }
 // Phones, tablets and the web app can open the camera; desktop apps pick a file.
 static bool get _hasCamera=>kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS;

 void _snack(String text){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}

 Future<void> _post(String body,{List<SarcadeAttachment> attachments=const []}) async {
   final raw=_recipient.text.trim();
   final recipients=raw.isEmpty?<String>[]:[SarcadeRecipient(id:raw,label:raw,type:_recipientType).protocolId];
   final m=SarcadeMessage(id:_uuid.v4(),eventId:widget.eventId,senderId:widget.actorId,recipientIds:recipients,priority:_priority,body:body,createdAt:DateTime.now().toUtc(),attachments:attachments);
   await widget.store.cacheMessage(m.toJson());
   await widget.sync.queue(objectId:m.id,objectType:'message',payload:m.toJson());
   if(mounted)setState((){}); _text.clear();
 }
 Future<void> _send() async {
   final body=_text.text.trim(); if(body.isEmpty)return;
   await _post(body);
 }

 Future<void> _photo() async {
   if(_picking)return;
   var source=ImageSource.gallery;
   if(_hasCamera){
     final chosen=await showModalBottomSheet<ImageSource>(context:context,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
       ListTile(leading:const Icon(Icons.photo_camera),title:const Text('Prendre une photo'),onTap:()=>Navigator.pop(c,ImageSource.camera)),
       ListTile(leading:const Icon(Icons.photo_library),title:const Text('Choisir une image'),onTap:()=>Navigator.pop(c,ImageSource.gallery)),
     ])));
     if(chosen==null)return;
     source=chosen;
   }
   setState(()=>_picking=true);
   try{
     // Resized and recompressed on the device: a few hundred kB, quick to send by radio relay or 4G.
     final shot=await ImagePicker().pickImage(source:source,maxWidth:1920,maxHeight:1920,imageQuality:80);
     if(shot==null)return;
     final bytes=await shot.readAsBytes();
     if(bytes.length>maxPhotoBytes){_snack('Photo trop lourde (10 Mo au maximum)');return;}
     if(!mounted)return;
     final caption=await showDialog<String>(context:context,builder:(_)=>_PhotoPreviewDialog(bytes:bytes,initialCaption:_text.text.trim()));
     if(caption==null)return;
     final mime=photoMimeType(shot.mimeType,shot.name);
     final now=DateTime.now().toUtc();
     final fileId=_uuid.v4();
     final name=photoFileName(now,mime);
     // Kept locally first: the photo survives a network loss and is sent before its message.
     await widget.store.saveAttachment(fileId,bytes);
     await widget.store.queueUpload({'file_id':fileId,'event_id':widget.eventId,'sender_id':widget.actorId,'name':name,'mime_type':mime,'created_at':now.toIso8601String()});
     await _post(caption.isEmpty?'Photo':caption,attachments:[SarcadeAttachment(fileId:fileId,name:name,mimeType:mime,sizeBytes:bytes.length)]);
   }catch(e){
     _snack('Photo impossible : $e');
   }finally{
     if(mounted)setState(()=>_picking=false);
   }
 }

 Future<void> _ack(SarcadeMessage m,String status) async {
   final a=SarcadeAck(id:_uuid.v4(),eventId:widget.eventId,messageId:m.id,actorId:widget.actorId,status:status,time:DateTime.now().toUtc());
   await widget.store.cacheAck(a.toJson());
   await widget.sync.queue(objectId:a.id,objectType:'ack',payload:a.toJson());
   if(mounted)setState((){});
 }
 @override void dispose(){_text.dispose();_recipient.dispose();super.dispose();}
 @override Widget build(BuildContext context){
   final messages=_messages,acks=_acks;
   return Scaffold(appBar:AppBar(title:Text('Messages · ${widget.store.pendingCount()} en attente')),body:Column(children:[
    Expanded(child:ListView.builder(itemCount:messages.length,itemBuilder:(c,i){
      final m=messages[i], mine=m.senderId==widget.actorId, ma=acks[m.id]??[];
      final photos=m.attachments.where((a)=>a.isImage).toList();
      return Card(child:ListTile(
        leading:Icon(m.priority=='immediate'?Icons.priority_high:m.priority=='urgent'?Icons.warning_amber:Icons.message),
        title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          if(photos.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:6),child:Wrap(spacing:6,runSpacing:6,children:[
            for(final p in photos)_PhotoThumb(key:ValueKey(p.fileId),attachment:p,api:widget.api,store:widget.store,eventId:widget.eventId),
          ])),
          Text(m.body),
        ]),
        subtitle:Text('${m.senderId} · ${m.priority}\nACK: ${ma.map((a)=>a.status).join(', ')}'),
        trailing:mine?null:PopupMenuButton<String>(onSelected:(s)=>_ack(m,s),itemBuilder:(_)=>const [
          PopupMenuItem(value:'received',child:Text('Reçu')),PopupMenuItem(value:'read',child:Text('Lu')),
          PopupMenuItem(value:'accepted',child:Text('Accepté')),PopupMenuItem(value:'rejected',child:Text('Refusé'))]),
      ));
    })),
    SafeArea(child:Row(children:[
      DropdownButton(value:_priority,items:const [DropdownMenuItem(value:'routine',child:Text('Routine')),DropdownMenuItem(value:'urgent',child:Text('Urgent')),DropdownMenuItem(value:'immediate',child:Text('Immédiat'))],onChanged:(v)=>setState(()=>_priority=v!)),
      SizedBox(width:90,child:DropdownButton(value:_recipientType,isExpanded:true,items:const [DropdownMenuItem(value:'team',child:Text('Équipe')),DropdownMenuItem(value:'user',child:Text('Agent'))],onChanged:(v)=>setState(()=>_recipientType=v!))),
      SizedBox(width:110,child:TextField(controller:_recipient,decoration:const InputDecoration(hintText:'ID ou vide'))),
      Expanded(child:TextField(controller:_text,maxLength:2048,decoration:const InputDecoration(hintText:'Message court',counterText:''))),
      IconButton(tooltip:'Envoyer une photo',onPressed:_picking?null:_photo,icon:_picking?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.photo_camera)),
      IconButton(tooltip:'Envoyer',onPressed:_send,icon:const Icon(Icons.send))
    ]))
   ]));
 }
}

/// Shows the photo before sending, with an optional caption.
class _PhotoPreviewDialog extends StatefulWidget {
 final Uint8List bytes; final String initialCaption;
 const _PhotoPreviewDialog({required this.bytes,required this.initialCaption});
 @override State<_PhotoPreviewDialog> createState()=>_PhotoPreviewDialogState();
}
class _PhotoPreviewDialogState extends State<_PhotoPreviewDialog>{
 late final _caption=TextEditingController(text:widget.initialCaption);
 @override void dispose(){_caption.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>AlertDialog(
   title:const Text('Envoyer la photo'),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
     ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.memory(widget.bytes,height:260,fit:BoxFit.contain)),
     const SizedBox(height:12),
     TextField(controller:_caption,maxLength:2048,textCapitalization:TextCapitalization.sentences,decoration:const InputDecoration(labelText:'Légende (facultative)')),
   ])),
   actions:[
     TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
     FilledButton.icon(onPressed:()=>Navigator.pop(context,_caption.text.trim()),icon:const Icon(Icons.send),label:const Text('Envoyer')),
   ],
 );
}

/// Thumbnail of a photo: from the local cache, else downloaded once and cached
/// so it stays visible offline.
class _PhotoThumb extends StatefulWidget {
 final SarcadeAttachment attachment; final SarcadeApi api; final LocalStore store; final String eventId;
 const _PhotoThumb({super.key,required this.attachment,required this.api,required this.store,required this.eventId});
 @override State<_PhotoThumb> createState()=>_PhotoThumbState();
}
class _PhotoThumbState extends State<_PhotoThumb>{
 late Future<Uint8List> _bytes=_load();
 Future<Uint8List> _load() async {
   final id=widget.attachment.fileId;
   final local=await widget.store.attachment(id);
   if(local!=null)return local;
   final bytes=Uint8List.fromList(await widget.api.downloadFile(widget.eventId,id));
   await widget.store.saveAttachment(id,bytes);
   return bytes;
 }
 @override Widget build(BuildContext context){
   final pending=widget.store.isUploadPending(widget.attachment.fileId);
   return SizedBox(width:160,height:120,child:FutureBuilder<Uint8List>(future:_bytes,builder:(c,s){
     if(s.hasError){
       return InkWell(onTap:()=>setState((){_bytes=_load();}),child:Container(color:Colors.black12,alignment:Alignment.center,
         child:const Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.broken_image_outlined),Text('Photo indisponible',style:TextStyle(fontSize:12)),Text('Toucher pour réessayer',style:TextStyle(fontSize:11))])));
     }
     if(!s.hasData)return Container(color:Colors.black12,alignment:Alignment.center,child:const CircularProgressIndicator(strokeWidth:2));
     return Stack(fit:StackFit.expand,children:[
       InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>_PhotoViewer(attachment:widget.attachment,bytes:s.data!))),
         child:ClipRRect(borderRadius:BorderRadius.circular(6),child:Image.memory(s.data!,fit:BoxFit.cover,cacheWidth:320))),
       if(pending)const Positioned(right:4,top:4,child:Tooltip(message:'En attente d’envoi',child:CircleAvatar(radius:12,child:Icon(Icons.cloud_upload_outlined,size:16)))),
     ]);
   }));
 }
}

/// Full screen photo with zoom, and saving to the device or as a download.
class _PhotoViewer extends StatelessWidget {
 final SarcadeAttachment attachment; final Uint8List bytes;
 const _PhotoViewer({required this.attachment,required this.bytes});
 @override Widget build(BuildContext context)=>Scaffold(
   backgroundColor:Colors.black,
   appBar:AppBar(title:Text(attachment.name),actions:[
     IconButton(tooltip:'Enregistrer',icon:const Icon(Icons.download),onPressed:() async {
       final messenger=ScaffoldMessenger.of(context);
       try{
         final path=await saveFile(attachment.name,bytes,mimeType:attachment.mimeType);
         messenger.showSnackBar(SnackBar(content:Text(canOpenSavedFiles?'Photo enregistrée : $path':'Photo téléchargée')));
       }catch(e){messenger.showSnackBar(SnackBar(content:Text('Échec de l’enregistrement : $e')));}
     }),
   ]),
   body:Center(child:InteractiveViewer(maxScale:6,child:Image.memory(bytes))),
 );
}
