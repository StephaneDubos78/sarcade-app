import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import '../../models/message.dart';
import '../groups/group_editor_page.dart';
import '../../models/recipient.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../platform/platform_services.dart';
import '../../services/notification_service.dart';
import '../../services/sarcade_api.dart';
import 'photo_attachment.dart';

class MessagesPage extends StatefulWidget {
 final SarcadeApi api; final String eventId,actorId; final OfflineSyncService sync; final LocalStore store;
 /// Text prepared by another screen (a point sent from the measure).
 final String? initialText;
 const MessagesPage({super.key,required this.api,required this.eventId,required this.actorId,required this.sync,required this.store,this.initialText});
 @override State<MessagesPage> createState()=>_MessagesPageState();
}
class _MessagesPageState extends State<MessagesPage>{
 final _text=TextEditingController(); final _recipient=TextEditingController(); final _uuid=const Uuid(); String _priority='routine';
 bool _picking=false;
 /// Conversation shown: a group, or every message when null.
 String? _groupId;
 /// Target when no group is selected: general broadcast or a direct recipient.
 bool _direct=false; String _recipientType='user';

 @override void initState(){super.initState();if(widget.initialText!=null)_text.text=widget.initialText!;_refreshGroups();}

 List<CommGroup> get _groups=>widget.store.groups(widget.eventId).map(CommGroup.fromJson).toList();
 CommGroup? get _group{if(_groupId==null)return null;for(final g in _groups){if(g.id==_groupId)return g;}return null;}

 Future<void> _refreshGroups() async {
   try{
     final list=await widget.api.groups(widget.eventId);
     for(final g in list){
       if(widget.sync.isPending(g['id'] as String))continue;
       if(g['deleted']==true){await widget.store.deleteGroup(g['id'] as String);}else{await widget.store.saveGroup(g);}
     }
     if(mounted)setState((){});
   }catch(_){/* offline: groups known on the device */}
 }

 List<SarcadeMessage> get _messages{
   final all=widget.store.messages().map(SarcadeMessage.fromJson).where((m)=>m.eventId==widget.eventId);
   final shown=_groupId==null?all:all.where((m)=>messageInGroup(m.recipientIds,_groupId!));
   return shown.toList()..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
 }
 Map<String,List<SarcadeAck>> get _acks {
   final out=<String,List<SarcadeAck>>{};
   for(final j in widget.store.acks()){final a=SarcadeAck.fromJson(j);(out[a.messageId]??=[]).add(a);}
   return out;
 }
 // Phones, tablets and the web app can open the camera; desktop apps pick a file.
 static bool get _hasCamera=>kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS;

 void _snack(String text){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}

 /// Recipients frozen at sending: the group, a direct recipient, or nobody
 /// (general broadcast).
 List<String> _recipients(){
   final g=_group;
   if(g!=null)return [g.recipientId];
   final raw=_recipient.text.trim();
   if(!_direct||raw.isEmpty)return <String>[];
   return [SarcadeRecipient(id:raw,label:raw,type:_recipientType).protocolId];
 }

 bool get _canWrite=>_group?.canSend(widget.actorId)??true;

 Future<void> _post(String body,{List<SarcadeAttachment> attachments=const []}) async {
   if(!_canWrite)return;
   final m=SarcadeMessage(id:_uuid.v4(),eventId:widget.eventId,senderId:widget.actorId,recipientIds:_recipients(),priority:_priority,body:body,createdAt:DateTime.now().toUtc(),attachments:attachments);
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
       ListTile(leading:const Icon(Icons.photo_camera),title:Text(S.t('messages.takePhoto')),onTap:()=>Navigator.pop(c,ImageSource.camera)),
       ListTile(leading:const Icon(Icons.photo_library),title:Text(S.t('messages.pickImage')),onTap:()=>Navigator.pop(c,ImageSource.gallery)),
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
     if(bytes.length>maxPhotoBytes){_snack(S.t('messages.photoTooLarge'));return;}
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
     await _post(caption.isEmpty?S.t('messages.photoDefault'):caption,attachments:[SarcadeAttachment(fileId:fileId,name:name,mimeType:mime,sizeBytes:bytes.length)]);
   }catch(e){
     _snack(S.t('messages.photoFailed',{'error':e}));
   }finally{
     if(mounted)setState(()=>_picking=false);
   }
 }

 Future<void> _ack(SarcadeMessage m,String status) async {
   final a=SarcadeAck(id:_uuid.v4(),eventId:widget.eventId,messageId:m.id,actorId:widget.actorId,status:status,time:DateTime.now().toUtc());
   await widget.store.cacheAck(a.toJson());
   await widget.sync.queue(objectId:a.id,objectType:'ack',payload:a.toJson());
   // An answer stops the reminders of an immediate message.
   await NotificationService().answered(m.id,status);
   if(mounted)setState((){});
 }

 Future<void> _editGroup(CommGroup? initial) async {
   final edit=await Navigator.push<GroupEdit>(context,MaterialPageRoute(builder:(_)=>GroupEditorPage(eventId:widget.eventId,actorId:widget.actorId,initial:initial)));
   if(edit==null)return;
   final g=edit.group;
   if(edit.deleted){
     await widget.store.deleteGroup(g.id);
     await widget.sync.queue(objectId:g.id,objectType:'comm_group',action:'delete',payload:{
       'id':g.id,'event_id':widget.eventId,'updated_by':widget.actorId,'updated_at':DateTime.now().toUtc().toIso8601String()});
     if(mounted)setState(()=>_groupId=null);
     return;
   }
   await widget.store.saveGroup(g.toJson());
   await widget.sync.queue(objectId:g.id,objectType:'comm_group',action:initial==null?'create':'update',payload:g.toJson());
   if(mounted)setState(()=>_groupId=g.archived?null:g.id);
 }

 String _recipientLabel(List<String> ids,Map<String,CommGroup> groups){
   if(ids.isEmpty)return S.t('messages.broadcast');
   return ids.map((r)=>r.startsWith('group:')?(groups[r.substring(6)]?.name??r):r.replaceFirst(RegExp(r'^(user|team):'),'')).join(', ');
 }

 @override void dispose(){_text.dispose();_recipient.dispose();super.dispose();}

 @override Widget build(BuildContext context){
   final messages=_messages,acks=_acks;
   final groups=sortedGroups(_groups);
   final byId={for(final g in _groups)g.id:g};
   final group=_group;
   return Scaffold(
    appBar:AppBar(title:Text(S.t('messages.title',{'n':widget.store.pendingCount()})),actions:[
      if(group!=null&&group.canManage(widget.actorId))IconButton(tooltip:S.t('groups.edit'),onPressed:()=>_editGroup(group),icon:const Icon(Icons.edit_outlined)),
      IconButton(tooltip:S.t('groups.new'),onPressed:()=>_editGroup(null),icon:const Icon(Icons.group_add_outlined)),
    ]),
    body:Column(children:[
     SizedBox(height:52,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:8,vertical:6),children:[
       Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(S.t('messages.all')),selected:_groupId==null,onSelected:(_)=>setState(()=>_groupId=null))),
       for(final g in groups)Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(
         avatar:CircleAvatar(backgroundColor:Color(g.color),radius:6),
         label:Text(g.listenOnly?'${g.name} · ${S.t('groups.listenOnlyBadge')}':g.name),
         selected:_groupId==g.id,onSelected:(_)=>setState(()=>_groupId=g.id),
       )),
     ])),
     if(group!=null&&(group.description.isNotEmpty||group.managers.isNotEmpty))Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Align(alignment:Alignment.centerLeft,child:Text(
       [if(group.description.isNotEmpty)group.description,if(group.radioChannel.isNotEmpty)group.radioChannel,S.t('groups.managers',{'names':group.managers.join(', ')})].join(' · '),
       style:Theme.of(context).textTheme.bodySmall))),
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
        subtitle:Text('${m.senderId} · ${S.t('priority.${m.priority}')} · ${S.t('messages.to',{'to':_recipientLabel(m.recipientIds,byId)})}\nACK: ${ma.map((a)=>S.t('ack.${a.status}')).join(', ')}'),
        trailing:mine?null:PopupMenuButton<String>(onSelected:(s)=>_ack(m,s),itemBuilder:(_)=>[
          for(final s in const ['received','read','accepted','rejected'])PopupMenuItem(value:s,child:Text(S.t('ack.$s')))]),
      ));
     })),
     if(group!=null&&!_canWrite)Material(color:Theme.of(context).colorScheme.surfaceContainerHighest,child:Padding(padding:const EdgeInsets.all(12),
       child:Row(children:[const Icon(Icons.campaign_outlined),const SizedBox(width:8),Expanded(child:Text(group.archived?S.t('groups.archivedNotice'):S.t('groups.cannotSend')))])))
     else SafeArea(child:Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Column(mainAxisSize:MainAxisSize.min,children:[
      if(group==null)Row(children:[
        ChoiceChip(label:Text(S.t('messages.broadcast')),selected:!_direct,onSelected:(_)=>setState(()=>_direct=false)),
        const SizedBox(width:6),
        ChoiceChip(label:Text(S.t('messages.direct')),selected:_direct,onSelected:(_)=>setState(()=>_direct=true)),
        if(_direct)...[
          const SizedBox(width:6),
          DropdownButton<String>(value:_recipientType,items:const [DropdownMenuItem(value:'user',child:Text('Agent')),DropdownMenuItem(value:'team',child:Text('Équipe'))],onChanged:(v)=>setState(()=>_recipientType=v??'user')),
          const SizedBox(width:6),
          Expanded(child:TextField(controller:_recipient,decoration:InputDecoration(hintText:S.t('messages.directHint'),isDense:true))),
        ],
      ]),
      Row(children:[
        DropdownButton<String>(value:_priority,items:[for(final p in const ['routine','urgent','immediate'])DropdownMenuItem(value:p,child:Text(S.t('priority.$p')))],onChanged:(v)=>setState(()=>_priority=v!)),
        const SizedBox(width:6),
        Expanded(child:TextField(controller:_text,maxLength:2048,minLines:1,maxLines:widget.initialText==null?1:6,decoration:InputDecoration(hintText:S.t('messages.hint'),counterText:''))),
        IconButton(tooltip:S.t('messages.photo'),onPressed:_picking?null:_photo,icon:_picking?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.photo_camera)),
        IconButton(tooltip:S.t('messages.send'),onPressed:_send,icon:const Icon(Icons.send)),
      ]),
     ]))),
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
   title:Text(S.t('messages.sendPhoto')),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
     ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.memory(widget.bytes,height:260,fit:BoxFit.contain)),
     const SizedBox(height:12),
     TextField(controller:_caption,maxLength:2048,textCapitalization:TextCapitalization.sentences,decoration:InputDecoration(labelText:S.t('messages.caption'))),
   ])),
   actions:[
     TextButton(onPressed:()=>Navigator.pop(context),child:Text(S.t('common.cancel'))),
     FilledButton.icon(onPressed:()=>Navigator.pop(context,_caption.text.trim()),icon:const Icon(Icons.send),label:Text(S.t('messages.send'))),
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
         child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.broken_image_outlined),Text(S.t('messages.photoUnavailable'),style:const TextStyle(fontSize:12)),Text(S.t('messages.tapRetry'),style:const TextStyle(fontSize:11))])));
     }
     if(!s.hasData)return Container(color:Colors.black12,alignment:Alignment.center,child:const CircularProgressIndicator(strokeWidth:2));
     return Stack(fit:StackFit.expand,children:[
       InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>_PhotoViewer(attachment:widget.attachment,bytes:s.data!))),
         child:ClipRRect(borderRadius:BorderRadius.circular(6),child:Image.memory(s.data!,fit:BoxFit.cover,cacheWidth:320))),
       if(pending)Positioned(right:4,top:4,child:Tooltip(message:S.t('messages.pendingUpload'),child:const CircleAvatar(radius:12,child:Icon(Icons.cloud_upload_outlined,size:16)))),
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
     IconButton(tooltip:S.t('messages.saveFile'),icon:const Icon(Icons.download),onPressed:() async {
       final messenger=ScaffoldMessenger.of(context);
       try{
         final path=await saveFile(attachment.name,bytes,mimeType:attachment.mimeType);
         messenger.showSnackBar(SnackBar(content:Text(canOpenSavedFiles?S.t('messages.photoSaved',{'path':path}):S.t('messages.photoDownloaded'))));
       }catch(e){messenger.showSnackBar(SnackBar(content:Text(S.t('messages.saveFailed',{'error':e}))));}
     }),
   ]),
   body:Center(child:InteractiveViewer(maxScale:6,child:Image.memory(bytes))),
 );
}
