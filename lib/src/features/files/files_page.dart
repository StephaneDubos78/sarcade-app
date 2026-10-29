import '../../l10n/strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../offline/local_store.dart';
import '../../platform/platform_services.dart';
import '../../models/shared_file.dart';
import '../../services/sarcade_api.dart';

/// Files screen (« Écran Fichiers enrichi », « Personnel », 28 Oct 2026):
/// the files of the event by folder of use, with search, the photos of the
/// messages gathered, and the « Personnel » folder of the person.
class FilesPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,actorId;
  /// Messages known on the device, to gather their photos.
  final LocalStore? store;
  const FilesPage({super.key,required this.api,required this.eventId,required this.actorId,this.store});
  @override State<FilesPage> createState()=>_FilesPageState();
}
class _FilesPageState extends State<FilesPage>{
  List<SarcadeSharedFile> files=[]; bool loading=true,uploading=false; String? error;
  final _search=TextEditingController(); String? _folder; bool _messagePhotos=false;
  ({List<SarcadeSharedFile> files,int used,int quota})? _personal; bool _personalLoaded=false;

  @override void initState(){super.initState();_load();_loadPersonal();}
  @override void dispose(){_search.dispose();super.dispose();}

  Future<void> _load() async {try{files=await widget.api.files(widget.eventId);error=null;}catch(e){error='$e';}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _loadPersonal() async {
    try{_personal=await widget.api.personalFiles();}catch(_){_personal=null;}
    if(mounted)setState(()=>_personalLoaded=true);
  }

  Set<String> get _photoIds{
    final s=widget.store; if(s==null)return const {};
    return {for(final j in s.messages())for(final a in SarcadeMessage.fromJson(j).attachments)if(a.isImage)a.fileId};
  }

  Future<({String name,List<int> bytes})?> _pick() async {
    final picked=await FilePicker.platform.pickFiles(withData:true);
    if(picked==null)return null; final f=picked.files.single;
    final bytes=await readPickedFile(f);
    if(bytes==null)return null;
    if(bytes.length>25*1024*1024){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.tooLarge'))));return null;}
    return (name:f.name,bytes:bytes);
  }

  Future<void> _upload() async {
    final folder=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(title:Text(S.t('files.chooseFolder'),style:Theme.of(c).textTheme.titleMedium)),
      for(final f in fileFolders)ListTile(leading:Icon(_folderIcon(f)),title:Text(S.t('files.folder.$f')),onTap:()=>Navigator.pop(c,f)),
    ])));
    if(folder==null)return;
    final p=await _pick(); if(p==null)return;
    setState(()=>uploading=true);
    try{await widget.api.uploadFile(widget.eventId,widget.actorId,p.name,'application/octet-stream',p.bytes,folder:folder);await _load();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.uploadFailed',{'error':e}))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  Future<void> _uploadPersonal() async {
    final p=await _pick(); if(p==null)return;
    setState(()=>uploading=true);
    try{await widget.api.uploadPersonalFile(p.name,p.bytes);await _loadPersonal();}
    on SarcadeHttpException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(e.body.contains('quota')?'files.quotaFull':'files.uploadFailed',{'error':e.statusCode}))));}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.uploadFailed',{'error':e}))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }

  Future<void> _openBytes(String name,String mime,Future<List<int>> Function() get) async {
    try{
      final bytes=await get();
      // Installed apps open the file; the web app hands it to the browser as a download.
      final path=await saveFile(name,bytes,temporary:true,mimeType:mime);
      if(canOpenSavedFiles)await openSavedFile(path);
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.downloadFailed',{'error':e}))));}
  }

  Future<void> _deletePersonal(SarcadeSharedFile f) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(content:Text(S.t('files.deleteConfirm',{'name':f.name})),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('files.delete')))]));
    if(ok!=true)return;
    try{await widget.api.deletePersonalFile(f.id);await _loadPersonal();}catch(_){}
  }

  static String _size(int n)=>n<1024?'$n o':n<1024*1024?'${(n/1024).toStringAsFixed(1)} Ko':'${(n/1024/1024).toStringAsFixed(1)} Mo';
  static String _date(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';}
  static IconData _folderIcon(String f)=>switch(f){'consignes'=>Icons.rule_folder_outlined,'cartes'=>Icons.map_outlined,'photos'=>Icons.photo_library_outlined,
    'fiches'=>Icons.fact_check_outlined,_=>Icons.folder_outlined};
  static IconData _fileIcon(SarcadeSharedFile f)=>f.isImage?Icons.image_outlined:f.mimeType=='application/pdf'?Icons.picture_as_pdf_outlined:Icons.insert_drive_file_outlined;

  Widget _eventTab(){
    if(loading)return const Center(child:CircularProgressIndicator());
    if(error!=null)return Center(child:Text(error!));
    final photos=_photoIds;
    var shown=filterFiles(files,query:_search.text,folder:_messagePhotos?null:_folder);
    if(_messagePhotos)shown=shown.where((f)=>photos.contains(f.id)).toList();
    Widget chip(String label,bool on,VoidCallback tap,{IconData? icon})=>Padding(padding:const EdgeInsets.only(right:6),
      child:ChoiceChip(avatar:icon==null?null:Icon(icon,size:16),label:Text(label),selected:on,showCheckmark:false,onSelected:(_)=>tap()));
    return Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),child:TextField(controller:_search,onChanged:(_)=>setState((){}),
        decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('files.search'),border:OutlineInputBorder(borderRadius:BorderRadius.circular(24))))),
      SizedBox(height:48,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),children:[
        chip(S.t('files.recent'),_folder==null&&!_messagePhotos,()=>setState((){_folder=null;_messagePhotos=false;}),icon:Icons.schedule),
        for(final f in fileFolders)chip(S.t('files.folder.$f'),_folder==f&&!_messagePhotos,()=>setState((){_folder=f;_messagePhotos=false;}),icon:_folderIcon(f)),
        if(photos.isNotEmpty)chip(S.t('files.messagePhotos'),_messagePhotos,()=>setState(()=>_messagePhotos=true),icon:Icons.chat_outlined),
      ])),
      Expanded(child:shown.isEmpty?Center(child:Text(S.t('files.none'))):ListView.separated(itemCount:shown.length,separatorBuilder:(_,_)=>const Divider(height:1),
        itemBuilder:(c,i){final f=shown[i];return ListTile(leading:Icon(_fileIcon(f)),title:Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis),
          subtitle:Text('${S.t('files.folder.${f.folder}')} · ${f.senderId} · ${_size(f.sizeBytes)} · ${_date(f.createdAt)}'),
          trailing:IconButton(tooltip:S.t('files.open'),icon:const Icon(Icons.download),onPressed:()=>_openBytes(f.name,f.mimeType,()=>widget.api.downloadFile(widget.eventId,f.id))),
          onTap:()=>_openBytes(f.name,f.mimeType,()=>widget.api.downloadFile(widget.eventId,f.id)));})),
    ]);
  }

  Widget _personalTab(){
    if(!_personalLoaded)return const Center(child:CircularProgressIndicator());
    final p=_personal;
    if(p==null)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(S.t('files.personalUnavailable'),textAlign:TextAlign.center)));
    final t=Theme.of(context);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,12,16,4),child:Text(S.t('files.personalHelp'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:4),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        LinearProgressIndicator(value:p.quota==0?0:(p.used/p.quota).clamp(0,1).toDouble()),
        const SizedBox(height:4),
        Text(S.t('files.usage',{'used':_size(p.used),'quota':_size(p.quota)}),style:t.textTheme.bodySmall),
      ])),
      const Divider(height:16),
      Expanded(child:p.files.isEmpty?Center(child:Text(S.t('files.none'))):ListView.separated(itemCount:p.files.length,separatorBuilder:(_,_)=>const Divider(height:1),
        itemBuilder:(c,i){final f=p.files[i];return ListTile(leading:Icon(_fileIcon(f)),title:Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis),
          subtitle:Text('${_size(f.sizeBytes)} · ${_date(f.createdAt)}'),
          trailing:IconButton(tooltip:S.t('files.delete'),icon:const Icon(Icons.delete_outline),onPressed:()=>_deletePersonal(f)),
          onTap:()=>_openBytes(f.name,f.mimeType,()=>widget.api.downloadPersonalFile(f.id)));})),
    ]);
  }

  @override Widget build(BuildContext context)=>DefaultTabController(length:2,child:Builder(builder:(context){
    final tabs=DefaultTabController.of(context);
    return Scaffold(
      appBar:AppBar(title:Text(S.t('map.files')),actions:[IconButton(tooltip:S.t('routes.refresh'),onPressed:(){_load();_loadPersonal();},icon:const Icon(Icons.refresh))],
        bottom:TabBar(tabs:[Tab(text:S.t('files.tabEvent')),Tab(text:S.t('files.tabPersonal'))])),
      floatingActionButton:AnimatedBuilder(animation:tabs,builder:(_,_)=>FloatingActionButton(tooltip:S.t('files.upload'),
        onPressed:uploading?null:(tabs.index==0?_upload:(_personal==null?null:_uploadPersonal)),
        child:uploading?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.add))),
      body:TabBarView(children:[_eventTab(),_personalTab()]),
    );
  }));
}
