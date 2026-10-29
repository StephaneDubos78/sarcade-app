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
import 'message_deletion.dart';
import '../settings/quick_messages_editor.dart' show defaultQuickMessages;
import '../dictation/dictation_button.dart';
import '../bearings/bearing_models.dart' show operatorInitials;

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
   _text.addListener(_onTextChanged);
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
 /// « Supprimer pour moi »: hidden on this device only.
 Set<String> get _hidden=>parseHidden(widget.store.preference(hiddenMessagesKey(widget.eventId)));
 Iterable<SarcadeMessage> get _eventMessages{final h=_hidden;return widget.store.messages().map(SarcadeMessage.fromJson).where((m)=>m.eventId==widget.eventId&&!h.contains(m.id));}
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


 /// The round button switches between the microphone and « Envoyer ».
 bool _wasEmpty=true;
 void _onTextChanged(){final e=_text.text.trim().isEmpty;if(e!=_wasEmpty&&mounted)setState(()=>_wasEmpty=e);}

 @override void dispose(){for(final w in _watch){w.cancel();}_text.removeListener(_onTextChanged);_text.dispose();_scroll.dispose();super.dispose();}

 Future<void> _addTemplate() async {
   try{
     final n=await widget.api.addGroupTemplate(widget.eventId,'adrasec');
     await _refreshGroups();
     _snack(S.t('groups.addedAdrasec',{'n':n}));
   }catch(_){
     _snack(S.t('event.offline'));
   }
 }

 /// Phone (29 Oct 2026, like WhatsApp): the list of the conversations first,
 /// a touch opens one full screen; the arrow comes back to the list. Opened
 /// for a purpose (a chat with an operator, a text to send): the chat at once.
 late bool _chatOpen=widget.initialPeer!=null||widget.initialText!=null;

 void _open(String key){
   if(!_chatOpen)setState(()=>_chatOpen=true);
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

 /// Chat colours (« Messages plus graphiques », 29 Oct 2026): plain light
 /// beige background, pale green bubbles for mine, white for the others;
 /// the same roles at night.
 bool get _night=>Theme.of(context).brightness==Brightness.dark;
 Color get _chatBg=>_night?const Color(0xFF0B141A):const Color(0xFFEFEAE2);
 Color get _mineBg=>_night?const Color(0xFF005C4B):const Color(0xFFD9FDD3);
 Color get _otherBg=>_night?const Color(0xFF202C33):Colors.white;

 /// Conversation list filters and search (computer).
 String _filter='all'; String _search='';
 Set<String> get _favConvs=>(widget.store.preference('msg_fav:${widget.eventId}')??'').split('|').where((s)=>s.isNotEmpty).toSet();
 Future<void> _toggleFavConv(String k) async {
   final f=_favConvs; if(!f.remove(k))f.add(k);
   await widget.store.setPreference('msg_fav:${widget.eventId}',f.isEmpty?null:f.join('|'));
   if(mounted)setState((){});
 }

 /// Round pastille of a person: the 2–3 letters of its map marker, in its
 /// operator colour.
 Widget _personAvatar(String id,{double r=15})=>CircleAvatar(radius:r,backgroundColor:Color(authorColor(id)),foregroundColor:Colors.white,
   child:Text(operatorInitials(id),style:TextStyle(fontSize:r*0.72,fontWeight:FontWeight.w700)));

 Widget _convIcon(String key,Map<String,CommGroup> by,{double r=18}){
   final g=groupOf(key);
   final color=key==allKey?const Color(0xFF546E7A):g!=null?Color(by[g]?.color??0xFF546E7A):Color(authorColor(peerOf(key)!));
   final icon=key==allKey?Icons.campaign_outlined:g!=null?Icons.forum_outlined:null;
   return CircleAvatar(radius:r,backgroundColor:color,foregroundColor:Colors.white,
     child:icon!=null?Icon(icon,size:r):Text(peerOf(key)!.characters.take(2).toString().toUpperCase(),style:TextStyle(fontSize:r*0.7,fontWeight:FontWeight.w700)));
 }

 /// Computer: list of the conversations on the left (WhatsApp Web): chips
 /// Toutes / Non lues / Favoris and a round search on top; pastille, name,
 /// « Auteur : texte », time on the right, unread count in SARCADE blue.
 Widget _convList(Map<String,CommGroup> by,Map<String,List<SarcadeAck>> acks){
   final t=Theme.of(context); final s=t.colorScheme;
   final lastBy=<String,SarcadeMessage>{};
   for(final m in _eventMessages){final k=conversationOf(m,widget.actorId,by);final l=lastBy[k];if(l==null||m.createdAt.isAfter(l.createdAt))lastBy[k]=m;}
   final fav=_favConvs; final q=_search.trim().toLowerCase();
   final keys=_conversations(by).where((k){
     if(_filter=='unread'&&_unreadIn(k,by,acks)==0)return false;
     if(_filter=='fav'&&!fav.contains(k))return false;
     if(q.isEmpty)return true;
     return _convName(k,by).toLowerCase().contains(q)||(lastBy[k]?.body.toLowerCase().contains(q)??false);
   }).toList();
   Widget chip(String id,String label)=>Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(label),selected:_filter==id,showCheckmark:false,
     onSelected:(_)=>setState(()=>_filter=id)));
   return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     Padding(padding:const EdgeInsets.fromLTRB(12,10,12,6),child:TextField(onChanged:(v)=>setState(()=>_search=v),
       decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('messages.search'),filled:true,
         fillColor:s.surfaceContainerHigh,border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none)))),
     Padding(padding:const EdgeInsets.fromLTRB(12,0,12,6),child:Row(children:[
       chip('all',S.t('messages.filterAll')),chip('unread',S.t('messages.filterUnread')),chip('fav',S.t('messages.filterFav'))])),
     Expanded(child:ListView(children:[for(final k in keys)Builder(builder:(_){
       final last=lastBy[k]; final n=_unreadIn(k,by,acks);
       return ListTile(selected:k==_conv,selectedTileColor:s.primaryContainer.withValues(alpha:0.45),
         leading:_convIcon(k,by,r:22),
         title:Text(_convName(k,by),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w600)),
         subtitle:last==null?null:Text('${last.senderId==widget.actorId?S.t('messages.you'):last.senderId} : ${last.deleted?S.t(last.deletedByPco?'messages.deletedByPco':'messages.deleted'):last.body}',maxLines:1,overflow:TextOverflow.ellipsis),
         // Time on the right, unread count in SARCADE blue, star of the
         // favourites (long press or right click to add or remove).
         trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
           if(last!=null)Text(_hm(last.createdAt),style:TextStyle(fontSize:12,color:n>0?s.primary:s.onSurfaceVariant)),
           const SizedBox(height:4),
           Row(mainAxisSize:MainAxisSize.min,children:[
             if(fav.contains(k))const Icon(Icons.star,size:16,color:Colors.amber),
             if(n>0)Container(margin:const EdgeInsets.only(left:4),padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
               decoration:BoxDecoration(color:s.primary,borderRadius:BorderRadius.circular(12)),
               child:Text('$n',style:TextStyle(color:s.onPrimary,fontSize:11,fontWeight:FontWeight.w700))),
           ]),
         ]),
         onLongPress:()=>_toggleFavConv(k),
         onTap:()=>_open(k));
     })])),
   ]);
 }

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
     if(!mine&&!m.deleted)for(final s in const ['received','read','accepted','rejected'])ListTile(leading:Icon(s=='rejected'?Icons.close:Icons.check),title:Text(S.t('ack.$s')),onTap:()=>Navigator.pop(c,s)),
     if(!m.deleted)ListTile(leading:const Icon(Icons.copy),title:Text(S.t('messages.copy')),onTap:()=>Navigator.pop(c,'copy')),
     ListTile(leading:const Icon(Icons.info_outline),title:Text(S.t('messages.info')),onTap:()=>Navigator.pop(c,'info')),
     if(!mine&&peerOf(_conv)==null)ListTile(leading:const Icon(Icons.chat_outlined),title:Text(S.t('messages.reply',{'who':m.senderId})),onTap:()=>Navigator.pop(c,'direct')),
     ListTile(leading:const Icon(Icons.delete_outline),title:Text(S.t('messages.delete')),onTap:()=>Navigator.pop(c,'delete')),
   ])));
   if(choice==null||!mounted)return;
   if(choice=='copy'){await Clipboard.setData(ClipboardData(text:m.body));_snack(S.t('messages.copied'));return;}
   if(choice=='info'){_showInfo(m,acks);return;}
   if(choice=='direct'){_open(directKey(m.senderId));return;}
   if(choice=='delete'){await _delete(m);return;}
   await _ack(m,choice);
 }

 /// « Supprimer pour moi » always; « Supprimer pour tous » for the author
 /// during 2 days, for the PCO always. Offline, the deletion waits in the
 /// Outbox like any change.
 Future<void> _delete(SarcadeMessage m) async {
   final pco=isPco(widget.actorId);
   final everyone=canDeleteForEveryone(m,widget.actorId,pco:pco,now:DateTime.now());
   final choice=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
     title:Text(S.t('messages.deleteTitle')),
     content:Text(everyone?S.t(m.senderId==widget.actorId?'messages.deleteHelpMine':'messages.deleteHelpPco'):S.t('messages.deleteHelpMe')),
     actions:[
       TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
       TextButton(onPressed:()=>Navigator.pop(c,'me'),child:Text(S.t('messages.deleteForMe'))),
       if(everyone)FilledButton(style:FilledButton.styleFrom(backgroundColor:Theme.of(c).colorScheme.error,foregroundColor:Theme.of(c).colorScheme.onError),
         onPressed:()=>Navigator.pop(c,'all'),child:Text(S.t('messages.deleteForAll'))),
     ]));
   if(choice==null)return;
   if(choice=='me'){
     await widget.store.setPreference(hiddenMessagesKey(widget.eventId),formatHidden({..._hidden,m.id}));
     if(mounted)setState((){});
     return;
   }
   final now=DateTime.now().toUtc();
   final byPco=pco&&m.senderId!=widget.actorId;
   await widget.store.cacheMessage(deletedMessage(m.toJson(),by:widget.actorId,byPco:byPco,at:now));
   await widget.sync.queue(objectId:m.id,objectType:'message',action:'delete',payload:{'id':m.id,'event_id':widget.eventId,'deleted_by':widget.actorId});
   if(mounted)setState((){});
 }

 Widget _bubble(SarcadeMessage m,List<SarcadeAck> ma,{required bool showAuthor}){
   final t=Theme.of(context); final s=t.colorScheme;
   final mine=m.senderId==widget.actorId;
   final photos=m.attachments.where((a)=>a.isImage).toList();
   final urgent=m.priority!='routine'; final immediate=m.priority=='immediate';
   final prio=immediate?s.error:const Color(0xFFE8710A);
   final sum=ackSummary(m.senderId,ma);
   final several=peerOf(_conv)==null;
   final grey=_night?const Color(0xFF8696A0):const Color(0xFF667781);
   final myAck=ma.where((a)=>a.actorId==widget.actorId).map((a)=>a.status).toSet();
   if(m.deleted)return _deletedBubble(m,ma,mine:mine,showAuthor:showAuthor,grey:grey);
   final needsAnswer=!mine&&immediate&&!myAck.contains('accepted')&&!myAck.contains('rejected');
   final meta=Row(mainAxisSize:MainAxisSize.min,children:[
     Text(_hm(m.createdAt),style:TextStyle(fontSize:11,color:grey)),
     if(mine)...[const SizedBox(width:4),_ticks(m,ma)],
   ]);
   final body=Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
     if(urgent)Padding(padding:const EdgeInsets.only(bottom:3),child:Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:1),
       decoration:BoxDecoration(color:prio.withValues(alpha:0.14),borderRadius:BorderRadius.circular(6)),
       child:Text(S.t('priority.${m.priority}').toUpperCase(),style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:prio,letterSpacing:0.4)))),
     if(showAuthor&&!mine)Padding(padding:const EdgeInsets.only(bottom:2),child:Text(m.senderId,
       style:TextStyle(fontWeight:FontWeight.w700,fontSize:13,color:Color(authorColor(m.senderId))))),
     if(photos.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:6),child:Wrap(spacing:6,runSpacing:6,children:[
       for(final p in photos)_PhotoThumb(key:ValueKey(p.fileId),attachment:p,api:widget.api,store:widget.store,eventId:widget.eventId),
     ])),
     Text(m.body,style:TextStyle(fontSize:15,height:1.3,color:s.onSurface,fontWeight:_unreadAtOpen.contains(m.id)?FontWeight.bold:null)),
     const SizedBox(height:2),
     Align(alignment:Alignment.bottomRight,widthFactor:1,child:meta),
     // Sent to several people: who read and received it, detail on touch.
     if(mine&&several&&sum.received>0)InkWell(onTap:()=>_showInfo(m,ma),child:Padding(padding:const EdgeInsets.only(top:2),
       child:Text(S.t('messages.ackSummary',{'r':sum.read,'n':sum.received}),style:const TextStyle(fontSize:11,color:Color(0xFF53BDEB))))),
     // Immediate: the acknowledgement stays one touch away.
     if(needsAnswer)Padding(padding:const EdgeInsets.only(top:6),child:Wrap(spacing:6,children:[
       FilledButton(style:FilledButton.styleFrom(backgroundColor:s.error,foregroundColor:s.onError,visualDensity:VisualDensity.compact),
         onPressed:()=>_ack(m,'accepted'),child:Text(S.t('order.accept'))),
       OutlinedButton(style:OutlinedButton.styleFrom(visualDensity:VisualDensity.compact),onPressed:()=>_ack(m,'rejected'),child:Text(S.t('order.refuse'))),
     ])),
   ]);
   const r=Radius.circular(10);
   final bubble=GestureDetector(onLongPress:()=>_actions(m,ma,mine),onSecondaryTap:()=>_actions(m,ma,mine),
     child:Container(margin:EdgeInsets.fromLTRB(mine?56:0,1,mine?0:56,1),padding:const EdgeInsets.fromLTRB(9,6,9,5),
       decoration:BoxDecoration(color:mine?_mineBg:_otherBg,
         // Small tail on the first bubble of a series.
         borderRadius:BorderRadius.only(topLeft:!mine&&showAuthor?const Radius.circular(2):r,topRight:mine&&showAuthor?const Radius.circular(2):r,bottomLeft:r,bottomRight:r),
         border:urgent?Border(left:BorderSide(color:prio,width:4)):null,
         boxShadow:const [BoxShadow(blurRadius:1,offset:Offset(0,1),color:Color(0x22000000))]),
       child:body));
   // Others in a channel: the pastille before the first message of a series.
   final avatar=!mine&&several?Padding(padding:const EdgeInsets.only(right:6,top:2),
     child:showAuthor?_personAvatar(m.senderId):const SizedBox(width:30)):null;
   return Padding(padding:EdgeInsets.fromLTRB(10,showAuthor?6:1,10,1),child:Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,
     child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:600),child:MergeSemantics(child:Row(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
       ?avatar,
       Flexible(child:bubble),
     ])))));
 }

 /// « Ce message a été supprimé » (« … par le PCO »), in italics, like WhatsApp.
 Widget _deletedBubble(SarcadeMessage m,List<SarcadeAck> ma,{required bool mine,required bool showAuthor,required Color grey}){
   const r=Radius.circular(10);
   return Padding(padding:EdgeInsets.fromLTRB(10,showAuthor?6:1,10,1),child:Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,
     child:GestureDetector(onLongPress:()=>_actions(m,ma,mine),onSecondaryTap:()=>_actions(m,ma,mine),
       child:Container(margin:EdgeInsets.fromLTRB(mine?56:0,1,mine?0:56,1),padding:const EdgeInsets.fromLTRB(9,6,9,5),
         decoration:BoxDecoration(color:mine?_mineBg:_otherBg,borderRadius:const BorderRadius.all(r),
           boxShadow:const [BoxShadow(blurRadius:1,offset:Offset(0,1),color:Color(0x22000000))]),
         child:Row(mainAxisSize:MainAxisSize.min,children:[
           Icon(Icons.block,size:16,color:grey),const SizedBox(width:6),
           Flexible(child:Text('${showAuthor&&!mine?'${m.senderId} · ':''}${S.t(m.deletedByPco?'messages.deletedByPco':'messages.deleted')}',
             style:TextStyle(fontSize:14,fontStyle:FontStyle.italic,color:grey))),
           const SizedBox(width:8),Text(_hm(m.createdAt),style:TextStyle(fontSize:11,color:grey)),
         ])))));
 }

 static const _emojis=['👍','👌','✅','❌','📍','📡','📻','🚗','🚶','⛰️','🌧️','☀️','⚠️','🆘','🔋','📶','🙏','😀','😅','👏'];
 Future<void> _pickEmoji() async {
   final e=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),
     child:Wrap(spacing:4,runSpacing:4,children:[for(final x in _emojis)InkWell(borderRadius:BorderRadius.circular(8),onTap:()=>Navigator.pop(c,x),
       child:Padding(padding:const EdgeInsets.all(8),child:Text(x,style:const TextStyle(fontSize:26))))]))));
   if(e==null)return;
   final sel=_text.selection; final v=_text.text;
   final at=sel.isValid?sel.start:v.length;
   _text.value=TextEditingValue(text:v.replaceRange(at,sel.isValid?sel.end:v.length,e),selection:TextSelection.collapsed(offset:at+e.length));
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
   return _quick=defaultQuickMessages();
 }
 Future<void> _sendQuickMessage() async {
   final list=await _quickMessages();
   if(!mounted)return;
   final pick=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:ListView(shrinkWrap:true,children:[
     for(final q in list)ListTile(leading:const Icon(Icons.bolt),title:Text(q),onTap:()=>Navigator.pop(c,q))])));
   if(pick!=null)await _post(pick);
 }

 /// Input bar laid out like WhatsApp on a phone (29 Oct 2026): « + » for
 /// the predefined messages and the priority, a wide rounded field with the
 /// emoji at its end, the camera, then one round button that dictates while
 /// the field is empty and sends once there is text.
 Widget _composer(){
   final s=Theme.of(context).colorScheme;
   final empty=_text.text.trim().isEmpty;
   final fieldColor=_night?const Color(0xFF2A3942):Colors.white;
   final iconColor=_night?const Color(0xFF8696A0):const Color(0xFF54656F);
   final prioColor=_priority=='immediate'?s.error:_priority=='urgent'?const Color(0xFFE8710A):null;
   return Material(color:_night?const Color(0xFF202C33):const Color(0xFFF0F2F5),child:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(4,6,6,6),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
     SizedBox(height:48,child:PopupMenuButton<String>(tooltip:S.t('messages.attach'),icon:Icon(Icons.add,size:28,color:iconColor),
       onSelected:(v){
         if(v=='quick'){_sendQuickMessage();}
         else if(v=='photo'){_photo();}
         else{setState(()=>_priority=v.substring(9));}
       },
       itemBuilder:(_)=>[
         PopupMenuItem(value:'quick',child:ListTile(leading:const Icon(Icons.bolt),title:Text(S.t('quick.title')))),
         PopupMenuItem(value:'photo',child:ListTile(leading:const Icon(Icons.photo_library_outlined),title:Text(S.t('messages.photo')))),
         const PopupMenuDivider(),
         for(final p in const ['routine','urgent','immediate'])PopupMenuItem(value:'priority.$p',child:ListTile(
           leading:Icon(_priority==p?Icons.radio_button_checked:Icons.radio_button_unchecked,
             color:p=='immediate'?s.error:p=='urgent'?const Color(0xFFE8710A):null),
           title:Text(S.t('priority.$p')))),
       ])),
     Expanded(child:Container(constraints:const BoxConstraints(minHeight:48),padding:const EdgeInsets.only(left:14,right:2),
       decoration:BoxDecoration(color:fieldColor,borderRadius:BorderRadius.circular(24)),
       child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
         // Urgent or immediate: a coloured chip in the field, one touch back to routine.
         if(prioColor!=null)Padding(padding:const EdgeInsets.only(right:6,bottom:12),child:InkWell(borderRadius:BorderRadius.circular(10),
           onTap:()=>setState(()=>_priority='routine'),
           child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
             decoration:BoxDecoration(color:prioColor.withValues(alpha:0.15),borderRadius:BorderRadius.circular(10)),
             child:Text(S.t('priority.$_priority'),style:TextStyle(fontSize:12,fontWeight:FontWeight.w600,color:prioColor))))),
         Expanded(child:Focus(onKeyEvent:_onKey,child:TextField(controller:_text,maxLength:2048,minLines:1,maxLines:widget.initialText==null?6:8,
           textCapitalization:TextCapitalization.sentences,style:const TextStyle(fontSize:17),
           decoration:InputDecoration(hintText:S.t('messages.hint'),counterText:'',border:InputBorder.none,isDense:true,
             contentPadding:const EdgeInsets.symmetric(vertical:13),
             helperText:_enterSends?S.t('messages.enterHint'):null)))),
         IconButton(tooltip:S.t('messages.emoji'),onPressed:_pickEmoji,icon:Icon(Icons.emoji_emotions_outlined,color:iconColor)),
       ]))),
     if(empty)SizedBox(height:48,child:_picking
       ?const Padding(padding:EdgeInsets.all(14),child:SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)))
       :IconButton(tooltip:S.t('messages.photo'),onPressed:_photo,icon:Icon(Icons.photo_camera_outlined,size:26,color:iconColor))),
     const SizedBox(width:4),
     SizedBox(width:48,height:48,child:empty
       ? DictationButton(controller:_text,filled:true)
       : IconButton.filled(tooltip:S.t('messages.send'),onPressed:_send,icon:const Icon(Icons.send))),
   ]))));
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
     Expanded(child:Container(color:_chatBg,child:Stack(children:[
       if(messages.isEmpty)Center(child:Text(S.t('messages.empty'),style:TextStyle(color:Theme.of(context).colorScheme.onSurfaceVariant))),
       ListView.builder(controller:_scroll,padding:const EdgeInsets.symmetric(vertical:8),itemCount:messages.length,itemBuilder:(c,i){
         final m=messages[i], ma=acks[m.id]??[];
         if(i>_maxBuilt)_maxBuilt=i;
         if(m.senderId!=widget.actorId)_autoRead(m,ma);
         final newDay=i==0||dayKey(messages[i-1].createdAt)!=dayKey(m.createdAt);
         final sameAuthor=!newDay&&i>0&&messages[i-1].senderId==m.senderId;
         final b=_bubble(m,ma,showAuthor:showAuthor&&!sameAuthor);
         if(i!=firstUnread&&!newDay)return b;
         return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
           if(newDay)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Center(child:Container(
             padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),
             decoration:BoxDecoration(color:_night?const Color(0xFF182229):Colors.white,borderRadius:BorderRadius.circular(8),
               boxShadow:const [BoxShadow(blurRadius:1,offset:Offset(0,1),color:Color(0x1A000000))]),
             child:Text(dayLabel(m.createdAt,DateTime.now(),today:S.t('messages.today'),yesterday:S.t('messages.yesterday')),
               style:TextStyle(fontSize:12,color:_night?const Color(0xFF8696A0):const Color(0xFF54656F)))))),
           if(i==firstUnread)Padding(key:_separatorKey,padding:const EdgeInsets.symmetric(vertical:6),child:Center(child:Chip(
             label:Text(S.t('messages.unreadSeparator',{'n':_unreadAtOpen.length})),visualDensity:VisualDensity.compact))),
           b,
         ]);
       }),
       if(!_atBottom)Positioned(right:12,bottom:12,child:Badge(
         isLabelVisible:below>0,label:Text('$below'),
         child:FloatingActionButton.small(heroTag:null,tooltip:S.t('messages.toBottom'),onPressed:()=>_toBottom(),child:const Icon(Icons.keyboard_arrow_down)))),
     ]))),
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
     final listOnly=!wide&&!_chatOpen;
     final newGroup=IconButton(tooltip:S.t('groups.new'),onPressed:()=>_editGroup(null),icon:const Icon(Icons.group_add_outlined));
     // PCO: channels of the ADRASEC model added in one touch (28 Oct 2026).
     final adrasec=isPco(widget.actorId)?PopupMenuButton<String>(onSelected:(_)=>_addTemplate(),itemBuilder:(_)=>[
       PopupMenuItem(value:'adrasec',child:Text(S.t('groups.addAdrasec')))]):null;
     final editGroup=group!=null&&group.canManage(widget.actorId)
       ?IconButton(tooltip:S.t('groups.edit'),onPressed:()=>_editGroup(group),icon:const Icon(Icons.edit_outlined)):null;
     if(listOnly){
       return Scaffold(
         appBar:AppBar(title:Text(S.t('messages.title',{'n':widget.store.pendingCount()})),actions:[newGroup,?adrasec]),
         body:_convList(by,acks));
     }
     final back=!wide&&widget.initialPeer==null&&widget.initialText==null;
     return Scaffold(
       appBar:AppBar(
         leading:back?BackButton(onPressed:()=>setState(()=>_chatOpen=false)):null,
         titleSpacing:back?0:null,
         title:Row(children:[
           if(!wide)...[_convIcon(_conv,by,r:18),const SizedBox(width:10)],
           Expanded(child:Text(wide?S.t('messages.title',{'n':widget.store.pendingCount()}):_convName(_conv,by),overflow:TextOverflow.ellipsis)),
         ]),
         actions:wide?[?editGroup,newGroup,?adrasec]:[?editGroup]),
       body:wide
         ? Row(children:[
             SizedBox(width:360,child:_convList(by,acks)),
             const VerticalDivider(width:1),
             Expanded(child:Column(children:[
               Material(elevation:0,child:ListTile(leading:_convIcon(_conv,by),title:Text(_convName(_conv,by),style:Theme.of(context).textTheme.titleMedium))),
               const Divider(height:1),
               Expanded(child:_chat(by,acks)),
             ])),
           ])
         : _chat(by,acks),
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
