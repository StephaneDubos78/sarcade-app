import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart';
import 'conversations.dart';
import '../../models/message.dart';
import '../../models/message_status.dart';
import '../../models/message_unread.dart';
import 'package:flutter/services.dart';
import '../groups/group_editor_page.dart';
import '../../offline/local_store.dart';
import '../../offline/sync_service.dart';
import '../../platform/platform_services.dart';
import '../../services/notification_service.dart';
import '../../services/sarcade_api.dart';
import 'photo_attachment.dart';
import '../dictation/dictation_button.dart';

class MessagesPage extends StatefulWidget {
 final SarcadeApi api; final String eventId,actorId; final OfflineSyncService sync; final LocalStore store;
 /// Text prepared by another screen (a point sent from the measure).
 final String? initialText;
 /// Direct chat to open (« Discuter » from an operator).
 final String? initialPeer;
 /// False while the screen is kept behind another tab (phone): nothing is
 /// marked seen or read until the operator comes back to it.
 final bool active;
 const MessagesPage({super.key,required this.api,required this.eventId,required this.actorId,required this.sync,required this.store,this.initialText,this.initialPeer,this.active=true});
 @override State<MessagesPage> createState()=>_MessagesPageState();
}
class _MessagesPageState extends State<MessagesPage>{
 final _text=TextEditingController(); final _uuid=const Uuid(); String _priority='routine';
 bool _picking=false;
 /// Conversation open (« Tous », a channel, a direct chat): it is also the
 /// recipient of what is written.
 late String _conv=widget.initialPeer!=null?directKey(widget.initialPeer!):allKey;
 String? get _groupId=>groupOf(_conv);

 final _watch=<StreamSubscription>[];
 /// Opening on the first unread message, ⌄ button, automatic « read ».
 final _scroll=ScrollController(); final _separatorKey=GlobalKey();
 bool _atBottom=true; int _maxBuilt=-1; final _readSent=<String>{};
 /// Unread when the screen opened: shown in bold; everything shown counts as
 /// seen (the pastille of the map goes back to zero).
 Set<String> _unreadAtOpen={};
 /// Computer keyboard: Enter sends, Alt+Enter or Shift+Enter adds a line.
 final bool _enterSends=enterSends(defaultTargetPlatform.name);
 // Messages received while this screen is open appear without the button.
 @override void initState(){
   super.initState();
   if(widget.initialText!=null)_text.text=widget.initialText!;
   _refreshGroups();
   _unreadAtOpen=unreadMessages(messages:_eventMessages,seen:widget.store.seenMessages(widget.eventId)??{},
     deviceId:widget.actorId,groups:{for(final g in _groups)g.id:g}).map((m)=>m.id).toSet();
   _markSeen();
   for(final s in widget.store.messageChanges()){_watch.add(s.listen((_){
     if(widget.active)_markSeen();
     if(!mounted)return;
     final follow=_atBottom; setState((){});
     // At the bottom, a new message stays in view (as on WhatsApp).
     if(follow)WidgetsBinding.instance.addPostFrameCallback((_)=>_toBottom());
   }));}
   _scroll.addListener((){
     final atBottom=!_scroll.hasClients||_scroll.position.pixels>=_scroll.position.maxScrollExtent-120;
     if(atBottom!=_atBottom&&mounted)setState(()=>_atBottom=atBottom);
   });
   WidgetsBinding.instance.addPostFrameCallback((_)=>_openPosition(0));
 }

 /// First unread message under its separator, else the most recent one.
 /// The list is built lazily: jump near the separator, then align on it.
 void _openPosition(int attempt){
   if(!mounted||!_scroll.hasClients)return;
   final shown=_messages; final first=firstUnreadIndex(shown,_unreadAtOpen);
   if(first==null){_toBottom();return;}
   final ctx=_separatorKey.currentContext;
   if(ctx!=null){Scrollable.ensureVisible(ctx,alignment:0.05);return;}
   if(attempt>=6)return;
   final max=_scroll.position.maxScrollExtent;
   _scroll.jumpTo((max*first/(shown.length<2?1:shown.length-1)).clamp(0,max));
   WidgetsBinding.instance.addPostFrameCallback((_)=>_openPosition(attempt+1));
 }
 void _toBottom([int attempt=0]){
   if(!mounted||!_scroll.hasClients)return;
   final max=_scroll.position.maxScrollExtent;
   _scroll.jumpTo(max);
   // Heights of items not yet built are estimated: repeat until it holds.
   if(attempt<5)WidgetsBinding.instance.addPostFrameCallback((_){if(_scroll.hasClients&&_scroll.position.maxScrollExtent!=max)_toBottom(attempt+1);});
 }

 /// A received message shown on screen goes to « read » by itself.
 @override void didUpdateWidget(MessagesPage old){
   super.didUpdateWidget(old);
   // Back on the Messages tab: same opening as a new screen (first unread).
   if(widget.active&&!old.active){
     _unreadAtOpen=unreadMessages(messages:_eventMessages,seen:widget.store.seenMessages(widget.eventId)??{},
       deviceId:widget.actorId,groups:{for(final g in _groups)g.id:g}).map((m)=>m.id).toSet();
     _markSeen();
   }
 }

 void _autoRead(SarcadeMessage m,List<SarcadeAck> acks){
   if(!widget.active)return;
   if(_readSent.contains(m.id)||!needsAutoRead(message:m,deviceId:widget.actorId,acks:acks))return;
   _readSent.add(m.id);
   WidgetsBinding.instance.addPostFrameCallback((_)=>unawaited(_ack(m,'read')));
 }

 Widget _ticks(SarcadeMessage m,List<SarcadeAck> acks){
   final status=sentStatus(pending:widget.sync.isPending(m.id),senderId:m.senderId,acks:acks);
   final readers=readersCount(m.senderId,acks);
   final several=m.recipientIds.isEmpty||m.recipientIds.any((r)=>r.startsWith('group:'));
   final (icon,color)=switch(status){
     SentStatus.pending=>(Icons.schedule,Colors.grey),
     SentStatus.sent=>(Icons.done,Colors.grey),
     SentStatus.received=>(Icons.done_all,Colors.grey),
     SentStatus.read=>(Icons.done_all,Colors.blue),
   };
   return Tooltip(message:S.t('messages.status.${status.name}'),child:Row(mainAxisSize:MainAxisSize.min,children:[
     Icon(icon,size:18,color:color),
     if(several&&readers>0)Padding(padding:const EdgeInsets.only(left:2),child:Text(S.t('messages.readBy',{'n':readers}),style:const TextStyle(fontSize:11,color:Colors.blue))),
   ]));
 }
 Iterable<SarcadeMessage> get _eventMessages=>widget.store.messages().map(SarcadeMessage.fromJson).where((m)=>m.eventId==widget.eventId);
 void _markSeen()=>unawaited(widget.store.markMessagesSeen(widget.eventId,_eventMessages.map((m)=>m.id)));

 /// Enter on a computer keyboard sends; Alt+Enter and Shift+Enter insert a
 /// new line. Text being composed (accents, IME) is left alone.
 KeyEventResult _onKey(FocusNode node,KeyEvent event){
   if(!_enterSends||event is! KeyDownEvent)return KeyEventResult.ignored;
   if(event.logicalKey!=LogicalKeyboardKey.enter&&event.logicalKey!=LogicalKeyboardKey.numpadEnter)return KeyEventResult.ignored;
   if(_text.value.composing.isValid)return KeyEventResult.ignored;
   final keys=HardwareKeyboard.instance;
   if(keys.isAltPressed||keys.isShiftPressed){
     final v=_text.value; final sel=v.selection.isValid?v.selection:TextSelection.collapsed(offset:v.text.length);
     final text=v.text.replaceRange(sel.start,sel.end,'\n');
     _text.value=TextEditingValue(text:text,selection:TextSelection.collapsed(offset:sel.start+1));
     return KeyEventResult.handled;
   }
   _send();
   return KeyEventResult.handled;
 }

 List<CommGroup> get _groups=>widget.store.groups(widget.eventId).map(CommGroup.fromJson).toList();
 CommGroup? get _group{
   final id=_groupId;
   for(final g in _groups){if(id==null?(_conv==allKey&&g.kind=='all'):g.id==id)return g;}
   return null;
 }
 Map<String,CommGroup> get _byId=>{for(final g in _groups)g.id:g};

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
   final by=_byId;
   final shown=_eventMessages.where((m)=>conversationOf(m,widget.actorId,by)==_conv);
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
 List<String> _recipients()=>recipientsFor(_conv,_byId);

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
     if(mounted)setState(()=>_conv=allKey);
     return;
   }
   await widget.store.saveGroup(g.toJson());
   await widget.sync.queue(objectId:g.id,objectType:'comm_group',action:initial==null?'create':'update',payload:g.toJson());
   if(mounted)setState(()=>_conv=g.archived?allKey:groupKey(g.id));
 }


 @override void dispose(){for(final w in _watch){w.cancel();}_text.dispose();_scroll.dispose();super.dispose();}

 Future<void> _addTemplate() async {
   try{
     final n=await widget.api.addGroupTemplate(widget.eventId,'adrasec');
     await _refreshGroups();
     _snack(S.t('groups.addedAdrasec',{'n':n}));
   }catch(_){
     _snack(S.t('event.offline'));
   }
 }

 void _open(String key){
   if(key==_conv)return;
   setState((){_conv=key;_maxBuilt=-1;});
   WidgetsBinding.instance.addPostFrameCallback((_)=>_toBottom());
 }

 String _convName(String key,Map<String,CommGroup> by){
   if(key==allKey)return by.values.firstWhere((g)=>g.kind=='all',orElse:()=>CommGroup(id:'',eventId:'',name:S.t('messages.everyone'),createdBy:'',updatedBy:'',updatedAt:DateTime(2000))).name;
   final g=groupOf(key); if(g!=null)return by[g]?.name??g;
   return peerOf(key)??key;
 }

 /// Conversations: « Tous », the channels, then the direct chats.
 List<String> _conversations(Map<String,CommGroup> by){
   return [allKey,for(final g in sortedGroups(_groups))if(g.kind!='all')groupKey(g.id),
     for(final p in {...directPeers(_eventMessages,widget.actorId,by),if(peerOf(_conv)!=null)peerOf(_conv)!})directKey(p)];
 }

 /// Unread messages of a conversation (received, not yet read by me).
 int _unreadIn(String key,Map<String,CommGroup> by,Map<String,List<SarcadeAck>> acks)=>_eventMessages.where((m)=>
   m.senderId!=widget.actorId&&conversationOf(m,widget.actorId,by)==key
   &&!(acks[m.id]??const []).any((a)=>a.actorId==widget.actorId&&a.status!='received')).length;

 Widget _convIcon(String key,Map<String,CommGroup> by,{double r=18}){
   final g=groupOf(key);
   final color=key==allKey?const Color(0xFF546E7A):g!=null?Color(by[g]?.color??0xFF546E7A):Color(authorColor(peerOf(key)!));
   final icon=key==allKey?Icons.campaign_outlined:g!=null?Icons.forum_outlined:null;
   return CircleAvatar(radius:r,backgroundColor:color,foregroundColor:Colors.white,
     child:icon!=null?Icon(icon,size:r):Text(peerOf(key)!.characters.take(2).toString().toUpperCase(),style:TextStyle(fontSize:r*0.7,fontWeight:FontWeight.w700)));
 }

 /// Computer: list of the conversations on the left (WhatsApp Web).
 Widget _convList(Map<String,CommGroup> by,Map<String,List<SarcadeAck>> acks){
   final t=Theme.of(context);
   final lastBy=<String,SarcadeMessage>{};
   for(final m in _eventMessages){final k=conversationOf(m,widget.actorId,by);final l=lastBy[k];if(l==null||m.createdAt.isAfter(l.createdAt))lastBy[k]=m;}
   return ListView(children:[for(final k in _conversations(by))Builder(builder:(_){
     final last=lastBy[k]; final n=_unreadIn(k,by,acks);
     return ListTile(selected:k==_conv,selectedTileColor:t.colorScheme.primaryContainer.withValues(alpha:0.4),
       leading:_convIcon(k,by),title:Text(_convName(k,by),maxLines:1,overflow:TextOverflow.ellipsis),
       subtitle:last==null?null:Text('${last.senderId==widget.actorId?S.t('messages.you'):last.senderId} : ${last.body}',maxLines:1,overflow:TextOverflow.ellipsis),
       trailing:n==0?null:Badge(label:Text('$n')),
       onTap:()=>_open(k));
   })]);
 }

 /// Phone: the conversations as chips above the chat.
 Widget _convChips(Map<String,CommGroup> by,Map<String,List<SarcadeAck>> acks)=>SizedBox(height:52,child:ListView(scrollDirection:Axis.horizontal,
   padding:const EdgeInsets.symmetric(horizontal:8,vertical:6),children:[for(final k in _conversations(by))Padding(padding:const EdgeInsets.only(right:6),
     child:Badge(isLabelVisible:k!=_conv&&_unreadIn(k,by,acks)>0,label:Text('${_unreadIn(k,by,acks)}'),child:ChoiceChip(
       avatar:_convIcon(k,by,r:9),label:Text(_convName(k,by)),selected:k==_conv,showCheckmark:false,onSelected:(_)=>_open(k))))]));

 static String _hm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

 /// Who received or read a message (touch on the summary, or « Infos »).
 void _showInfo(SarcadeMessage m,List<SarcadeAck> acks){
   final by=<String,SarcadeAck>{};
   for(final a in acks){if(a.actorId==m.senderId)continue;final b=by[a.actorId];if(b==null||_rank(a.status)>_rank(b.status))by[a.actorId]=a;}
   showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:ListView(shrinkWrap:true,children:[
     ListTile(title:Text(S.t('messages.info'),style:Theme.of(c).textTheme.titleMedium)),
     if(by.isEmpty)ListTile(title:Text(S.t('messages.noAck'))),
     for(final e in by.entries)ListTile(leading:Icon(e.value.status=='received'?Icons.done_all:Icons.done_all,color:e.value.status=='received'?Colors.grey:Colors.blue),
       title:Text(e.key),trailing:Text('${S.t('ack.${e.value.status}')} · ${_hm(e.value.time)}')),
   ])));
 }
 static int _rank(String s)=>switch(s){'received'=>0,'read'=>1,_=>2};

 /// Long press (phone) or right click (computer): actions on a message.
 Future<void> _actions(SarcadeMessage m,List<SarcadeAck> acks,bool mine) async {
   final choice=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
     if(!mine)for(final s in const ['received','read','accepted','rejected'])ListTile(leading:Icon(s=='rejected'?Icons.close:Icons.check),title:Text(S.t('ack.$s')),onTap:()=>Navigator.pop(c,s)),
     ListTile(leading:const Icon(Icons.copy),title:Text(S.t('messages.copy')),onTap:()=>Navigator.pop(c,'copy')),
     ListTile(leading:const Icon(Icons.info_outline),title:Text(S.t('messages.info')),onTap:()=>Navigator.pop(c,'info')),
     if(!mine&&peerOf(_conv)==null)ListTile(leading:const Icon(Icons.chat_outlined),title:Text(S.t('messages.reply',{'who':m.senderId})),onTap:()=>Navigator.pop(c,'direct')),
   ])));
   if(choice==null||!mounted)return;
   if(choice=='copy'){await Clipboard.setData(ClipboardData(text:m.body));_snack(S.t('messages.copied'));return;}
   if(choice=='info'){_showInfo(m,acks);return;}
   if(choice=='direct'){_open(directKey(m.senderId));return;}
   await _ack(m,choice);
 }

 Widget _bubble(SarcadeMessage m,List<SarcadeAck> ma,{required bool showAuthor}){
   final t=Theme.of(context); final s=t.colorScheme;
   final mine=m.senderId==widget.actorId;
   final photos=m.attachments.where((a)=>a.isImage).toList();
   final urgent=m.priority!='routine';
   final sum=ackSummary(m.senderId,ma);
   final several=peerOf(_conv)==null;
   final meta=Row(mainAxisSize:MainAxisSize.min,children:[
     if(urgent)Padding(padding:const EdgeInsets.only(right:6),child:Text(S.t('priority.${m.priority}'),
       style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:m.priority=='immediate'?s.error:Colors.orange))),
     Text(_hm(m.createdAt),style:TextStyle(fontSize:11,color:s.onSurfaceVariant)),
     if(mine)...[const SizedBox(width:4),_ticks(m,ma)],
   ]);
   final body=Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
     if(showAuthor&&!mine)Padding(padding:const EdgeInsets.only(bottom:2),child:Text(m.senderId,
       style:TextStyle(fontWeight:FontWeight.w700,fontSize:13,color:Color(authorColor(m.senderId))))),
     if(photos.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:6),child:Wrap(spacing:6,runSpacing:6,children:[
       for(final p in photos)_PhotoThumb(key:ValueKey(p.fileId),attachment:p,api:widget.api,store:widget.store,eventId:widget.eventId),
     ])),
     Text(m.body,style:_unreadAtOpen.contains(m.id)?const TextStyle(fontWeight:FontWeight.bold):null),
     const SizedBox(height:2),
     Align(alignment:Alignment.bottomRight,widthFactor:1,child:meta),
     // Sent to several people: who read and received it, detail on touch.
     if(mine&&several&&sum.received>0)InkWell(onTap:()=>_showInfo(m,ma),child:Padding(padding:const EdgeInsets.only(top:2),
       child:Text(S.t('messages.ackSummary',{'r':sum.read,'n':sum.received}),style:const TextStyle(fontSize:11,color:Colors.blue)))),
   ]);
   final bubble=GestureDetector(onLongPress:()=>_actions(m,ma,mine),onSecondaryTap:()=>_actions(m,ma,mine),
     child:Container(margin:EdgeInsets.fromLTRB(mine?48:8,2,mine?8:48,2),padding:const EdgeInsets.fromLTRB(10,6,10,6),
       decoration:BoxDecoration(color:mine?s.primaryContainer:s.surfaceContainerHigh,borderRadius:BorderRadius.only(
         topLeft:const Radius.circular(14),topRight:const Radius.circular(14),
         bottomLeft:Radius.circular(mine?14:4),bottomRight:Radius.circular(mine?4:14)),
         border:urgent?Border.all(color:m.priority=='immediate'?s.error:Colors.orange,width:1.5):null),
       child:body));
   return Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:MergeSemantics(child:bubble)));
 }

 /// Predefined messages (ATAK 6): the list of the PCO for the event, else
 /// the usual ones; one touch sends.
 List<String>? _quick;
 Future<List<String>> _quickMessages() async {
   if(_quick!=null)return _quick!;
   try{
     final e=await widget.api.event(widget.eventId);
     final l=((e['settings'] as Map?)?['quick_messages'] as List?)?.whereType<String>().toList()??const [];
     if(l.isNotEmpty)return _quick=l;
   }catch(_){/* offline: the usual list */}
   return _quick=[for(final k in const ['inPlace','signalHeard','signalLost','backToPco','needHelp','copy'])S.t('quick.$k')];
 }
 Future<void> _sendQuickMessage() async {
   final list=await _quickMessages();
   if(!mounted)return;
   final pick=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:ListView(shrinkWrap:true,children:[
     for(final q in list)ListTile(leading:const Icon(Icons.bolt),title:Text(q),onTap:()=>Navigator.pop(c,q))])));
   if(pick!=null)await _post(pick);
 }

 Widget _composer(){
   final s=Theme.of(context).colorScheme;
   return SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(6,4,6,6),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
     IconButton(tooltip:S.t('quick.title'),onPressed:_sendQuickMessage,icon:const Icon(Icons.bolt)),
     IconButton(tooltip:S.t('messages.photo'),onPressed:_picking?null:_photo,
       icon:_picking?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.add_circle_outline)),
     Expanded(child:Container(padding:const EdgeInsets.only(left:14,right:4),decoration:BoxDecoration(color:s.surfaceContainerHighest,borderRadius:BorderRadius.circular(24)),
       child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
         Expanded(child:Focus(onKeyEvent:_onKey,child:TextField(controller:_text,maxLength:2048,minLines:1,maxLines:widget.initialText==null?5:7,
           decoration:InputDecoration(hintText:S.t('messages.hint'),counterText:'',border:InputBorder.none,
             helperText:_enterSends?S.t('messages.enterHint'):null)))),
         DictationButton(controller:_text),
       ]))),
     const SizedBox(width:4),
     DropdownButtonHideUnderline(child:DropdownButton<String>(value:_priority,borderRadius:BorderRadius.circular(12),
       items:[for(final p in const ['routine','urgent','immediate'])DropdownMenuItem(value:p,child:Text(S.t('priority.$p'),
         style:TextStyle(fontSize:13,color:p=='immediate'?s.error:p=='urgent'?Colors.orange:null)))],
       onChanged:(v)=>setState(()=>_priority=v!))),
     IconButton.filled(tooltip:S.t('messages.send'),onPressed:_send,icon:const Icon(Icons.send)),
   ])));
 }

 Widget _chat(Map<String,CommGroup> by,Map<String,List<SarcadeAck>> acks){
   final messages=_messages;
   final firstUnread=firstUnreadIndex(messages,_unreadAtOpen);
   final below=[for(var i=_maxBuilt+1;i<messages.length;i++)if(messages[i].senderId!=widget.actorId)i].length;
   final group=_group;
   final showAuthor=peerOf(_conv)==null;
   return Column(children:[
     if(group!=null&&(group.description.isNotEmpty||group.managers.isNotEmpty))Padding(padding:const EdgeInsets.fromLTRB(14,4,14,4),child:Align(alignment:Alignment.centerLeft,child:Text(
       [if(group.description.isNotEmpty)group.description,if(group.radioChannel.isNotEmpty)group.radioChannel,S.t('groups.managers',{'names':group.managers.join(', ')})].join(' · '),
       style:Theme.of(context).textTheme.bodySmall))),
     Expanded(child:Stack(children:[
       if(messages.isEmpty)Center(child:Text(S.t('messages.empty'),style:TextStyle(color:Theme.of(context).colorScheme.onSurfaceVariant))),
       ListView.builder(controller:_scroll,padding:const EdgeInsets.symmetric(vertical:8),itemCount:messages.length,itemBuilder:(c,i){
         final m=messages[i], ma=acks[m.id]??[];
         if(i>_maxBuilt)_maxBuilt=i;
         if(m.senderId!=widget.actorId)_autoRead(m,ma);
         final sameAuthor=i>0&&messages[i-1].senderId==m.senderId;
         final b=_bubble(m,ma,showAuthor:showAuthor&&!sameAuthor);
         if(i!=firstUnread)return b;
         return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
           Padding(key:_separatorKey,padding:const EdgeInsets.symmetric(vertical:6),child:Center(child:Chip(
             label:Text(S.t('messages.unreadSeparator',{'n':_unreadAtOpen.length})),visualDensity:VisualDensity.compact))),
           b,
         ]);
       }),
       if(!_atBottom)Positioned(right:12,bottom:12,child:Badge(
         isLabelVisible:below>0,label:Text('$below'),
         child:FloatingActionButton.small(heroTag:null,tooltip:S.t('messages.toBottom'),onPressed:()=>_toBottom(),child:const Icon(Icons.keyboard_arrow_down)))),
     ])),
     if(group!=null&&!_canWrite)Material(color:Theme.of(context).colorScheme.surfaceContainerHighest,child:Padding(padding:const EdgeInsets.all(12),
       child:Row(children:[const Icon(Icons.campaign_outlined),const SizedBox(width:8),Expanded(child:Text(group.archived?S.t('groups.archivedNotice'):S.t('groups.cannotSend')))])))
     else _composer(),
   ]);
 }

 @override Widget build(BuildContext context){
   final by=_byId, acks=_acks;
   final group=_group;
   return LayoutBuilder(builder:(context,c){
     final wide=c.maxWidth>=900;
     return Scaffold(
       appBar:AppBar(title:Row(children:[
         if(!wide)...[_convIcon(_conv,by,r:14),const SizedBox(width:10)],
         Expanded(child:Text(wide?S.t('messages.title',{'n':widget.store.pendingCount()}):_convName(_conv,by),overflow:TextOverflow.ellipsis)),
       ]),actions:[
         if(group!=null&&group.canManage(widget.actorId))IconButton(tooltip:S.t('groups.edit'),onPressed:()=>_editGroup(group),icon:const Icon(Icons.edit_outlined)),
         IconButton(tooltip:S.t('groups.new'),onPressed:()=>_editGroup(null),icon:const Icon(Icons.group_add_outlined)),
         // PCO: channels of the ADRASEC model added in one touch (28 Oct 2026).
         if(isPco(widget.actorId))PopupMenuButton<String>(onSelected:(_)=>_addTemplate(),itemBuilder:(_)=>[
           PopupMenuItem(value:'adrasec',child:Text(S.t('groups.addAdrasec')))]),
       ]),
       body:wide
         ? Row(children:[
             SizedBox(width:320,child:_convList(by,acks)),
             const VerticalDivider(width:1),
             Expanded(child:Column(children:[
               Material(elevation:0,child:ListTile(leading:_convIcon(_conv,by),title:Text(_convName(_conv,by),style:Theme.of(context).textTheme.titleMedium))),
               const Divider(height:1),
               Expanded(child:_chat(by,acks)),
             ])),
           ])
         : Column(children:[_convChips(by,acks),const Divider(height:1),Expanded(child:_chat(by,acks))]),
     );
   });
 }
}

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
 // The photo can reach the server long after its message: sender still
 // uploading, or photo held on the sender's device by the low-bandwidth mode
 // until the PCO lifts it (test of 23 Oct 2026). The thumbnail shows
 // « Photo en attente » and retries by itself, every 5 s then every 20 s,
 // for an hour; after that, a tap retries.
 Uint8List? _bytes; bool _waiting=false, _gaveUp=false; Timer? _retry; int _attempt=0;
 @override void initState(){super.initState();_load();}
 @override void dispose(){_retry?.cancel();super.dispose();}
 Future<void> _load() async {
   final id=widget.attachment.fileId;
   final local=await widget.store.attachment(id);
   if(local!=null){if(mounted)setState(()=>_bytes=local);return;}
   try{
     final bytes=Uint8List.fromList(await widget.api.downloadFile(widget.eventId,id));
     await widget.store.saveAttachment(id,bytes);
     if(mounted)setState((){_bytes=bytes;_waiting=false;_gaveUp=false;});
   }catch(_){
     if(!mounted)return;
     _attempt++;
     final elapsed=_attempt<=12?_attempt*5:60+(_attempt-12)*20;
     if(elapsed>=3600){setState((){_waiting=false;_gaveUp=true;});return;}
     setState(()=>_waiting=true);
     _retry=Timer(Duration(seconds:_attempt<12?5:20),_load);
   }
 }
 void _retryNow(){_retry?.cancel();setState((){_attempt=0;_gaveUp=false;_waiting=true;});_load();}
 @override Widget build(BuildContext context){
   final pending=widget.store.isUploadPending(widget.attachment.fileId);
   final bytes=_bytes;
   Widget placeholder(IconData icon,String title,String? hint)=>InkWell(onTap:_retryNow,child:Container(color:Colors.black12,alignment:Alignment.center,padding:const EdgeInsets.all(6),
     child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(icon),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:12)),if(hint!=null)Text(hint,textAlign:TextAlign.center,style:const TextStyle(fontSize:11))])));
   return SizedBox(width:160,height:120,child:bytes!=null
     ?Stack(fit:StackFit.expand,children:[
       InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>_PhotoViewer(attachment:widget.attachment,bytes:bytes))),
         child:ClipRRect(borderRadius:BorderRadius.circular(6),child:Image.memory(bytes,fit:BoxFit.cover,cacheWidth:320))),
       if(pending)Positioned(right:4,top:4,child:Tooltip(message:S.t('messages.pendingUpload'),child:const CircleAvatar(radius:12,child:Icon(Icons.cloud_upload_outlined,size:16)))),
     ])
     :_gaveUp?placeholder(Icons.broken_image_outlined,S.t('messages.photoUnavailable'),S.t('messages.tapRetry'))
     :_waiting?placeholder(Icons.hourglass_top,'Photo en attente','envoi différé par l’expéditeur (liaison faible)')
     :Container(color:Colors.black12,alignment:Alignment.center,child:const CircularProgressIndicator(strokeWidth:2)));
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
