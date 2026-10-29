import '../../l10n/strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/comm_group.dart' show isPco;
import '../../models/message.dart';
import '../../offline/local_store.dart';
import '../../platform/platform_services.dart';
import '../../models/shared_file.dart';
import '../../services/sarcade_api.dart';
import 'file_tree.dart';

/// Files screen (« Écran Fichiers enrichi », « Personnel », 28 Oct 2026;
/// « sous-dossiers et interface plus soignée », 29 Oct 2026): folders up to
/// 3 levels with a breadcrumb, « + Nouveau » (folder, import), files with a
/// coloured icon by type and a ⋮ menu, list or grid, quota gauge.
class FilesPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,actorId;
  /// Messages known on the device, to gather their photos.
  final LocalStore? store;
  const FilesPage({super.key,required this.api,required this.eventId,required this.actorId,this.store});
  @override State<FilesPage> createState()=>_FilesPageState();
}

class _FilesPageState extends State<FilesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs=TabController(length:2,vsync:this)..addListener((){if(mounted)setState((){});});
  List<SarcadeSharedFile> _files=[]; Set<String> _folders={}; bool _loading=true, _uploading=false; String? _error;
  ({List<SarcadeSharedFile> files,int used,int quota,List<String> folders})? _personal; bool _personalLoaded=false;
  final _search=TextEditingController(); bool _messagePhotos=false;
  String _eventPath='', _personalPath='';
  bool get _grid=>widget.store?.preference('files_grid')=='1';

  bool get _personalTab=>_tabs.index==1;
  String get _path=>_personalTab?_personalPath:_eventPath;
  set _path(String v){if(_personalTab){_personalPath=v;}else{_eventPath=v;}}
  /// Folders of the event: the PCO organises them; personal: the owner.
  bool get _canOrganise=>_personalTab||isPco(widget.actorId);

  @override void initState(){super.initState();_load();_loadPersonal();}
  @override void dispose(){_search.dispose();_tabs.dispose();super.dispose();}

  Future<void> _load() async {
    try{
      final r=await widget.api.filesWithFolders(widget.eventId);
      _files=r.files; _folders=allFolders(r.folders,r.files); _error=null;
    }catch(e){_error='$e';}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _loadPersonal() async {
    try{_personal=await widget.api.personalFiles();}catch(_){_personal=null;}
    if(mounted)setState(()=>_personalLoaded=true);
  }
  Future<void> _reload()=>_personalTab?_loadPersonal():_load();

  Set<String> get _photoIds{
    final s=widget.store; if(s==null)return const {};
    return {for(final j in s.messages())for(final a in SarcadeMessage.fromJson(j).attachments)if(a.isImage)a.fileId};
  }

  void _say(String text)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
  String _errorText(Object e){
    if(e is SarcadeHttpException){
      for(final k in const ['folder_exists','folder_not_empty','folder_too_deep','folder_inside_itself','invalid_folder','quota']){
        if(e.body.contains(k))return S.t('files.err.$k');
      }
    }
    return S.t('files.actionFailed');
  }
  String? get _eventIdOrNull=>_personalTab?null:widget.eventId;

  Future<({String name,List<int> bytes})?> _pick() async {
    final picked=await FilePicker.platform.pickFiles(withData:true);
    if(picked==null)return null; final f=picked.files.single;
    final bytes=await readPickedFile(f);
    if(bytes==null)return null;
    if(bytes.length>25*1024*1024){if(mounted)_say(S.t('files.tooLarge'));return null;}
    return (name:f.name,bytes:bytes);
  }

  Future<void> _import() async {
    final p=await _pick(); if(p==null)return;
    setState(()=>_uploading=true);
    try{
      if(_personalTab){await widget.api.uploadPersonalFile(p.name,p.bytes,folder:_path);await _loadPersonal();}
      else{await widget.api.uploadFile(widget.eventId,widget.actorId,p.name,'application/octet-stream',p.bytes,folder:_path);await _load();}
    }catch(e){if(mounted)_say(e is SarcadeHttpException&&e.body.contains('quota')?S.t('files.quotaFull'):S.t('files.uploadFailed',{'error':e is SarcadeHttpException?e.statusCode:e}));}
    finally{if(mounted)setState(()=>_uploading=false);}
  }

  Future<String?> _askName(String title,{String initial=''}) async {
    final ctrl=TextEditingController(text:initial);
    final v=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:Text(title),
      content:TextField(controller:ctrl,autofocus:true,maxLength:60,decoration:InputDecoration(labelText:S.t('files.name'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text),child:Text(S.t('common.ok')))]));
    ctrl.dispose();
    return v;
  }

  Future<void> _run(Future<void> Function() action) async {
    try{await action();await _reload();}catch(e){if(mounted)_say(_errorText(e));}
  }

  Future<void> _newFolder() async {
    if(folderDepth(_path)>=maxFolderDepth){_say(S.t('files.err.folder_too_deep'));return;}
    final v=await _askName(S.t('files.newFolder')); if(v==null)return;
    final name=validFolderName(v); if(name==null){_say(S.t('files.err.invalid_folder'));return;}
    await _run(()=>widget.api.createFolder(_eventIdOrNull,joinFolder(_path,name),actorId:_personalTab?null:widget.actorId));
  }

  Future<void> _renameFolder(String path) async {
    final v=await _askName(S.t('files.rename'),initial:folderName(path)); if(v==null)return;
    final name=validFolderName(v); if(name==null){_say(S.t('files.err.invalid_folder'));return;}
    await _run(()=>widget.api.moveFolder(_eventIdOrNull,path,joinFolder(parentFolder(path),name),actorId:_personalTab?null:widget.actorId));
  }

  /// Destination folder: the root or any folder (not [exclude] nor inside it).
  Future<String?> _chooseFolder({String? exclude,int extraDepth=0}) async {
    final all=[..._currentFolders]..sort();
    final ok=[for(final f in all)if((exclude==null||(f!=exclude&&!f.startsWith('$exclude/')))&&folderDepth(f)+extraDepth<=maxFolderDepth)f];
    return showModalBottomSheet<String>(context:context,showDragHandle:true,isScrollControlled:true,builder:(c)=>SafeArea(child:ConstrainedBox(
      constraints:BoxConstraints(maxHeight:MediaQuery.sizeOf(c).height*0.7),child:ListView(shrinkWrap:true,children:[
        ListTile(title:Text(S.t('files.moveTo'),style:Theme.of(c).textTheme.titleMedium)),
        ListTile(leading:const Icon(Icons.home_outlined),title:Text(S.t(_personalTab?'files.tabPersonal':'files.tabEvent')),onTap:()=>Navigator.pop(c,'')),
        for(final f in ok)ListTile(contentPadding:EdgeInsets.only(left:16.0+20*(folderDepth(f)-1),right:16),
          leading:const Icon(Icons.folder,color:folderColor),title:Text(folderLabel(f)),onTap:()=>Navigator.pop(c,f)),
      ]))));
  }

  int _subDepth(String path){var d=0;for(final f in _currentFolders){if(f.startsWith('$path/'))d=d<folderDepth(f)-folderDepth(path)?folderDepth(f)-folderDepth(path):d;}return d;}

  Future<void> _moveFolder(String path) async {
    final to=await _chooseFolder(exclude:path,extraDepth:1+_subDepth(path)); if(to==null)return;
    await _run(()=>widget.api.moveFolder(_eventIdOrNull,path,joinFolder(to,folderName(path)),actorId:_personalTab?null:widget.actorId));
  }

  Future<void> _deleteFolder(String path) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(content:Text(S.t('files.deleteFolderConfirm',{'name':folderLabel(path)})),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('files.delete')))]));
    if(ok!=true)return;
    await _run(()=>widget.api.deleteFolder(_eventIdOrNull,path,actorId:_personalTab?null:widget.actorId));
  }

  Future<void> _renameFile(SarcadeSharedFile f) async {
    final v=await _askName(S.t('files.rename'),initial:f.name); if(v==null||v.trim().isEmpty)return;
    await _run(()=>widget.api.moveFile(_eventIdOrNull,f.id,name:v.trim(),actorId:_personalTab?null:widget.actorId));
  }
  Future<void> _moveFile(SarcadeSharedFile f) async {
    final to=await _chooseFolder(); if(to==null)return;
    await _run(()=>widget.api.moveFile(_eventIdOrNull,f.id,folder:to,actorId:_personalTab?null:widget.actorId));
  }
  Future<void> _deletePersonal(SarcadeSharedFile f) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(content:Text(S.t('files.deleteConfirm',{'name':f.name})),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('files.delete')))]));
    if(ok!=true)return;
    await _run(()=>widget.api.deletePersonalFile(f.id));
  }

  Future<List<int>> _bytes(SarcadeSharedFile f)=>_personalTab?widget.api.downloadPersonalFile(f.id):widget.api.downloadFile(widget.eventId,f.id);
  Future<void> _open(SarcadeSharedFile f,{bool keep=false}) async {
    try{
      final bytes=await _bytes(f);
      // Installed apps open the file; the web app hands it to the browser as a download.
      final path=await saveFile(f.name,bytes,temporary:!keep,mimeType:f.mimeType);
      if(!keep&&canOpenSavedFiles)await openSavedFile(path);
      if(keep&&mounted)_say(S.t('files.saved'));
    }catch(e){if(mounted)_say(S.t('files.downloadFailed',{'error':e}));}
  }

  static String _size(int n)=>n<1024?'$n o':n<1024*1024?'${(n/1024).toStringAsFixed(1)} Ko':'${(n/1024/1024).toStringAsFixed(1)} Mo';
  static String _date(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';}

  Iterable<SarcadeSharedFile> get _currentFiles=>_personalTab?(_personal?.files??const []):_files;
  Set<String> get _currentFolders=>_personalTab?allFolders(_personal?.folders??const [],_personal?.files??const []):_folders;

  Widget _fileMenu(SarcadeSharedFile f)=>PopupMenuButton<String>(tooltip:S.t('files.more'),
    onSelected:(a){switch(a){case 'open':_open(f);case 'save':_open(f,keep:true);case 'rename':_renameFile(f);case 'move':_moveFile(f);case 'delete':_deletePersonal(f);}},
    itemBuilder:(_)=>[
      PopupMenuItem(value:'open',child:ListTile(leading:const Icon(Icons.open_in_new),title:Text(S.t('files.open')))),
      PopupMenuItem(value:'save',child:ListTile(leading:const Icon(Icons.download),title:Text(S.t('files.download')))),
      if(_canOrganise)PopupMenuItem(value:'rename',child:ListTile(leading:const Icon(Icons.edit_outlined),title:Text(S.t('files.rename')))),
      if(_canOrganise)PopupMenuItem(value:'move',child:ListTile(leading:const Icon(Icons.drive_file_move_outline),title:Text(S.t('files.move')))),
      if(_personalTab)PopupMenuItem(value:'delete',child:ListTile(leading:const Icon(Icons.delete_outline),title:Text(S.t('files.delete')))),
    ]);

  Widget? _folderMenu(String path)=>!_canOrganise?null:PopupMenuButton<String>(tooltip:S.t('files.more'),
    onSelected:(a){switch(a){case 'rename':_renameFolder(path);case 'move':_moveFolder(path);case 'delete':_deleteFolder(path);}},
    itemBuilder:(_)=>[
      PopupMenuItem(value:'rename',child:ListTile(leading:const Icon(Icons.edit_outlined),title:Text(S.t('files.rename')))),
      PopupMenuItem(value:'move',child:ListTile(leading:const Icon(Icons.drive_file_move_outline),title:Text(S.t('files.move')))),
      PopupMenuItem(value:'delete',child:ListTile(leading:const Icon(Icons.delete_outline),title:Text(S.t('files.deleteFolder')))),
    ]);

  Widget _kindIcon(({IconData icon,Color color}) k,{double size=40})=>Container(width:size,height:size,
    decoration:BoxDecoration(color:k.color.withValues(alpha:0.12),borderRadius:BorderRadius.circular(10)),child:Icon(k.icon,color:k.color,size:size*0.6));

  Widget _items(List<String> folders,List<SarcadeSharedFile> files,{bool showFolder=false}){
    final t=Theme.of(context);
    if(folders.isEmpty&&files.isEmpty)return _empty();
    if(_grid){
      return GridView.extent(maxCrossAxisExtent:180,padding:const EdgeInsets.fromLTRB(12,8,12,96),mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.05,children:[
        for(final f in folders)_tile(icon:_kindIcon((icon:Icons.folder,color:folderColor),size:56),title:folderLabel(f),subtitle:'',onTap:()=>setState(()=>_path=f),menu:_folderMenu(f)),
        for(final f in files)_tile(icon:_kindIcon(fileKind(f),size:56),title:f.name,subtitle:'${_size(f.sizeBytes)} · ${_date(f.createdAt)}',onTap:()=>_open(f),menu:_fileMenu(f)),
      ]);
    }
    return ListView(padding:const EdgeInsets.only(bottom:96),children:[
      for(final f in folders)ListTile(leading:_kindIcon((icon:Icons.folder,color:folderColor)),title:Text(folderLabel(f),style:const TextStyle(fontWeight:FontWeight.w500)),
        subtitle:Text(S.t('files.folderCount',{'n':_currentFiles.where((x)=>normalFolder(x.folder)==f||normalFolder(x.folder).startsWith('$f/')).length})),
        onTap:()=>setState(()=>_path=f),trailing:_folderMenu(f)),
      for(final f in files)ListTile(leading:_kindIcon(fileKind(f)),title:Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text([if(showFolder&&normalFolder(f.folder).isNotEmpty)folderLabel(normalFolder(f.folder)),if(!_personalTab)f.senderId,_size(f.sizeBytes),_date(f.createdAt)].join(' · '),
          style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        onTap:()=>_open(f),trailing:_fileMenu(f)),
    ]);
  }

  Widget _tile({required Widget icon,required String title,required String subtitle,required VoidCallback onTap,Widget? menu})=>Card(elevation:0,
    child:InkWell(borderRadius:BorderRadius.circular(16),onTap:onTap,child:Stack(children:[
      Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        icon,const Spacer(),
        Text(title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w500)),
        if(subtitle.isNotEmpty)Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodySmall),
      ])),
      if(menu!=null)Positioned(top:0,right:0,child:menu),
    ])));

  /// Illustrated empty state with « Importer ».
  Widget _empty(){
    final t=Theme.of(context);
    return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(width:96,height:96,decoration:BoxDecoration(color:t.colorScheme.primaryContainer,shape:BoxShape.circle),
        child:Icon(_personalTab?Icons.folder_shared_outlined:Icons.folder_open_outlined,size:48,color:t.colorScheme.primary)),
      const SizedBox(height:16),
      Text(S.t(_path.isNotEmpty?'files.emptyFolder':_personalTab?'files.nonePersonal':'files.noneEvent'),style:t.textTheme.titleMedium,textAlign:TextAlign.center),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:_uploading?null:_import,icon:const Icon(Icons.upload_file),label:Text(S.t('files.import'))),
    ])));
  }

  /// Breadcrumb, « + Nouveau », list / grid.
  Widget _toolbar(){
    final crumbs=breadcrumb(S.t(_personalTab?'files.tabPersonal':'files.tabEvent'),_path);
    final t=Theme.of(context);
    return Padding(padding:const EdgeInsets.fromLTRB(12,6,8,2),child:Row(children:[
      if(_path.isNotEmpty)IconButton(tooltip:S.t('files.up'),onPressed:()=>setState(()=>_path=parentFolder(_path)),icon:const Icon(Icons.arrow_upward)),
      Expanded(child:SingleChildScrollView(scrollDirection:Axis.horizontal,reverse:true,child:Row(children:[
        for(var i=0;i<crumbs.length;i++)...[
          if(i>0)Icon(Icons.chevron_right,size:18,color:t.colorScheme.onSurfaceVariant),
          TextButton(onPressed:i==crumbs.length-1?null:()=>setState(()=>_path=crumbs[i].path),
            style:TextButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:6),disabledForegroundColor:t.colorScheme.onSurface),
            child:Text(crumbs[i].label,style:TextStyle(fontWeight:i==crumbs.length-1?FontWeight.w700:FontWeight.w500))),
        ],
      ]))),
      IconButton(tooltip:S.t(_grid?'files.asList':'files.asGrid'),onPressed:() async {await widget.store?.setPreference('files_grid',_grid?null:'1');if(mounted)setState((){});},
        icon:Icon(_grid?Icons.view_list_outlined:Icons.grid_view_outlined)),
      const SizedBox(width:4),
      MenuAnchor(builder:(c,ctl,_)=>FilledButton.icon(onPressed:_uploading?null:()=>ctl.isOpen?ctl.close():ctl.open(),
          icon:_uploading?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.add),label:Text(S.t('files.new'))),
        menuChildren:[
          if(_canOrganise)MenuItemButton(leadingIcon:const Icon(Icons.create_new_folder_outlined),onPressed:_newFolder,child:Text(S.t('files.newFolder'))),
          MenuItemButton(leadingIcon:const Icon(Icons.upload_file),onPressed:_import,child:Text(S.t('files.import'))),
        ]),
    ]));
  }

  Widget _eventTab(){
    if(_loading)return const Center(child:CircularProgressIndicator());
    if(_error!=null)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(S.t('event.offline')),TextButton(onPressed:_load,child:Text(S.t('common.retry')))])));
    final photos=_photoIds; final q=_search.text.trim();
    final searching=q.isNotEmpty||_messagePhotos;
    var flat=filterFiles(_files,query:q);
    if(_messagePhotos)flat=flat.where((f)=>photos.contains(f.id)).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,8,12,0),child:Row(children:[
        Expanded(child:TextField(controller:_search,onChanged:(_)=>setState((){}),
          decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),hintText:S.t('files.search'),filled:true,
            fillColor:Theme.of(context).colorScheme.surfaceContainerHigh,border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none)))),
        if(photos.isNotEmpty)...[const SizedBox(width:8),FilterChip(avatar:const Icon(Icons.chat_outlined,size:16),label:Text(S.t('files.messagePhotos')),
          selected:_messagePhotos,onSelected:(v)=>setState(()=>_messagePhotos=v))],
      ])),
      if(!searching)_toolbar(),
      const SizedBox(height:4),
      Expanded(child:searching?_items(const [],flat,showFolder:true):_items(childFolders(_folders,_eventPath),filesIn(_files,_eventPath))),
    ]);
  }

  Widget _personalTabView(){
    if(!_personalLoaded)return const Center(child:CircularProgressIndicator());
    final p=_personal;
    if(p==null)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(S.t('files.personalUnavailable'),textAlign:TextAlign.center)));
    final folders=allFolders(p.folders,p.files);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      _toolbar(),
      Expanded(child:_items(childFolders(folders,_personalPath),filesIn(p.files,_personalPath))),
    ]);
  }

  /// Compact quota gauge, orange above 80 %.
  Widget? _quota(){
    final p=_personal; if(!_personalTab||p==null||p.quota<=0)return null;
    final ratio=(p.used/p.quota).clamp(0.0,1.0);
    final color=ratio>0.8?const Color(0xFFE8710A):Theme.of(context).colorScheme.primary;
    return Padding(padding:const EdgeInsets.only(right:8),child:Tooltip(message:S.t('files.usage',{'used':_size(p.used),'quota':_size(p.quota)}),child:Row(mainAxisSize:MainAxisSize.min,children:[
      SizedBox(width:72,child:ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:ratio,minHeight:6,color:color,
        backgroundColor:color.withValues(alpha:0.15)))),
      const SizedBox(width:6),
      Text('${(ratio*100).round()} %',style:TextStyle(fontSize:12,color:color,fontWeight:FontWeight.w600)),
    ])));
  }

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    return Scaffold(
      appBar:AppBar(title:Text(S.t('map.files')),actions:[
        ?_quota(),
        IconButton(tooltip:S.t('routes.refresh'),onPressed:(){_load();_loadPersonal();},icon:const Icon(Icons.refresh))],
        bottom:PreferredSize(preferredSize:const Size.fromHeight(70),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          // Tabs on the left, underlined (not spread over the whole width).
          TabBar(controller:_tabs,isScrollable:true,tabAlignment:TabAlignment.start,tabs:[Tab(text:S.t('files.tabEvent')),Tab(text:S.t('files.tabPersonal'))]),
          Padding(padding:const EdgeInsets.fromLTRB(16,4,16,4),child:Text(S.t(_personalTab?'files.personalHelpShort':'files.eventHelpShort'),
            maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant))),
        ]))),
      body:TabBarView(controller:_tabs,children:[_eventTab(),_personalTabView()]),
    );
  }
}
