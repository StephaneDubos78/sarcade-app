import '../../l10n/strings.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/comm_group.dart' show isPco;
import '../../models/message.dart';
import '../../offline/local_store.dart';
import '../../platform/platform_services.dart';
import '../../models/shared_file.dart';
import '../../services/sarcade_api.dart';
import 'drawings_section.dart';
import 'file_tree.dart';
export 'drawings_section.dart' show DrawingFileActions;
import '../../ui/action_buttons.dart';
import '../../ui/link_status.dart';

/// Files screen (« Écran Fichiers enrichi », « Personnel », 28 Oct 2026;
/// « sous-dossiers et interface plus soignée », 29 Oct 2026): folders up to
/// 3 levels with a breadcrumb, « + Nouveau » (folder, import), files with a
/// coloured icon by type and a ⋮ menu, list or grid, quota gauge.
class FilesPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,actorId;
  /// Messages known on the device, to gather their photos.
  final LocalStore? store;
  /// Import and export of the drawings (PCO and admin, from the map).
  final DrawingFileActions? drawings;
  const FilesPage({super.key,required this.api,required this.eventId,required this.actorId,this.store,this.drawings});
  @override State<FilesPage> createState()=>_FilesPageState();
}

class _FilesPageState extends State<FilesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs=TabController(length:2,vsync:this)..addListener((){if(mounted)setState((){});});
  List<SarcadeSharedFile> _files=[]; Set<String> _folders={}; bool _loading=true, _uploading=false; String? _error;
  ({List<SarcadeSharedFile> files,int used,int quota,List<String> folders})? _personal; bool _personalLoaded=false;
  final _search=TextEditingController(); bool _messagePhotos=false;
  String _eventPath='', _personalPath='';
  bool get _grid=>widget.store?.preference('files_grid')=='1';
  /// Computer (29 Oct 2026, « comme l'Explorateur Windows »): folder tree on
  /// the left, details of the selected folder on the right.
  bool _wide=false;
  final Set<String> _expanded={'e:','p:'};
  String _sortBy='name'; bool _sortUp=true;

  bool get _personalTab=>_tabs.index==1;
  String get _path=>_personalTab?_personalPath:_eventPath;
  set _path(String v){if(_personalTab){_personalPath=v;}else{_eventPath=v;}}
  /// Folders of the event: the PCO organises them; personal: the owner.
  bool get _canOrganise=>_personalTab||isPco(widget.actorId);

  StreamSubscription<List<({String name,List<int> bytes})>>? _drops;
  @override void initState(){super.initState();_load();_loadPersonal();_drops=desktopFileDrops().listen(_dropped);}
  @override void dispose(){_drops?.cancel();_search.dispose();_tabs.dispose();super.dispose();}

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
    await _upload([p]);
  }

  /// Uploads into the open folder; true when every file went.
  Future<bool> _upload(List<({String name,List<int> bytes})> files) async {
    setState(()=>_uploading=true);
    try{
      for(final p in files){
        if(_personalTab){await widget.api.uploadPersonalFile(p.name,p.bytes,folder:_path);}
        else{await widget.api.uploadFile(widget.eventId,widget.actorId,p.name,'application/octet-stream',p.bytes,folder:_path);}
      }
      await _reload();
      return true;
    }catch(e){if(mounted)_say(e is SarcadeHttpException&&e.body.contains('quota')?S.t('files.quotaFull'):S.t('files.uploadFailed',{'error':e is SarcadeHttpException?e.statusCode:e}));return false;}
    finally{if(mounted)setState(()=>_uploading=false);}
  }

  /// Files dropped from the Explorer or the desktop: imported into the
  /// open folder (validated on 30 Oct 2026, 2 h 44).
  Future<void> _dropped(List<({String name,List<int> bytes})> files) async {
    if(!mounted||_uploading)return;
    final ok=[for(final f in files)if(f.bytes.length<=25*1024*1024)f];
    if(ok.length<files.length)_say(S.t('files.tooLarge'));
    if(ok.isEmpty)return;
    final where=_path.isEmpty?S.t(_personalTab?'files.tabPersonal':'files.tabEvent'):folderLabel(_path);
    if(await _upload(ok)&&mounted)_say(S.t('files.dropImported',{'n':ok.length,'name':where}));
  }

  /// Drag and drop between folders (« Fichiers, glisser-déposer »): same
  /// rights as « Déplacer », a « Déplacé dans X » message with Annuler.
  bool _canDrop(_Drag d,String to){
    if(d.personal!=_personalTab||!_canOrganise)return false;
    final f=d.file;
    if(f!=null)return normalFolder(f.folder)!=to;
    final from=d.folder!;
    if(to==from||to.startsWith('$from/')||parentFolder(from)==to)return false;
    return folderDepth(to)+1+_subDepth(from)<=maxFolderDepth;
  }

  Future<void> _dropOn(_Drag d,String to) async {
    final ev=_eventIdOrNull; final actor=_personalTab?null:widget.actorId;
    final where=to.isEmpty?S.t(_personalTab?'files.tabPersonal':'files.tabEvent'):folderLabel(to);
    Future<void> Function() undo;
    try{
      final f=d.file;
      if(f!=null){
        final back=normalFolder(f.folder);
        await widget.api.moveFile(ev,f.id,folder:to,actorId:actor);
        undo=()=>widget.api.moveFile(ev,f.id,folder:back,actorId:actor);
      }else{
        final from=d.folder!, dest=joinFolder(to,folderName(from));
        await widget.api.moveFolder(ev,from,dest,actorId:actor);
        undo=()=>widget.api.moveFolder(ev,dest,from,actorId:actor);
      }
      await _reload();
    }catch(e){if(mounted)_say(_errorText(e));return;}
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.movedTo',{'name':where})),
      action:SnackBarAction(label:S.t('common.undo'),onPressed:()=>unawaited(_run(undo)))));
  }

  /// Phones and tablets: long press then drag; computers: the mouse.
  bool get _touch=>defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS;

  Widget _draggable(_Drag d,{required IconData icon,required Color color,required String label,required Widget child}){
    if(!_canOrganise)return child;
    final feedback=Material(elevation:6,borderRadius:BorderRadius.circular(12),color:Theme.of(context).colorScheme.surfaceContainerHigh,
      child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Row(mainAxisSize:MainAxisSize.min,children:[
        Icon(icon,color:color,size:22),const SizedBox(width:8),
        ConstrainedBox(constraints:const BoxConstraints(maxWidth:240),child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis)),
      ])));
    final faded=Opacity(opacity:0.4,child:child);
    return _touch?LongPressDraggable<_Drag>(data:d,feedback:feedback,childWhenDragging:faded,child:child)
      :Draggable<_Drag>(data:d,feedback:feedback,childWhenDragging:faded,child:child);
  }

  /// A folder that accepts a drop: highlighted while something is over it.
  Widget _target(String folder,Widget Function(bool over) build)=>DragTarget<_Drag>(
    onWillAcceptWithDetails:(e)=>_canDrop(e.data,folder),
    onAcceptWithDetails:(e)=>unawaited(_dropOn(e.data,folder)),
    builder:(c,cand,_)=>build(cand.isNotEmpty));

  Widget _hl(bool over,Widget child,{double radius=8}){
    if(!over)return child;
    final s=Theme.of(context).colorScheme;
    return DecoratedBox(decoration:BoxDecoration(color:s.primaryContainer,borderRadius:BorderRadius.circular(radius),
      border:Border.all(color:s.primary,width:2)),child:child);
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
    if(_wide&&!_grid)return _details(folders,files,showFolder:showFolder);
    if(_grid){
      return GridView.extent(maxCrossAxisExtent:180,padding:const EdgeInsets.fromLTRB(12,8,12,96),mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.05,children:[
        for(final f in folders)_target(f,(over)=>_hl(over,radius:16,_draggable((file:null,folder:f,personal:_personalTab),icon:Icons.folder,color:folderColor,label:folderLabel(f),
          child:_tile(icon:_kindIcon((icon:Icons.folder,color:folderColor),size:56),title:folderLabel(f),subtitle:'',onTap:()=>_select(_personalTab,f),menu:_folderMenu(f))))),
        for(final f in files)_draggable((file:f,folder:null,personal:_personalTab),icon:fileKind(f).icon,color:fileKind(f).color,label:f.name,
          child:_tile(icon:_kindIcon(fileKind(f),size:56),title:f.name,subtitle:'${_size(f.sizeBytes)} · ${_date(f.createdAt)}',onTap:()=>_open(f),menu:_fileMenu(f))),
      ]);
    }
    return ListView(padding:const EdgeInsets.only(bottom:96),children:[
      for(final f in folders)_target(f,(over)=>_hl(over,_draggable((file:null,folder:f,personal:_personalTab),icon:Icons.folder,color:folderColor,label:folderLabel(f),
        child:ListTile(leading:_kindIcon((icon:Icons.folder,color:folderColor)),title:Text(folderLabel(f),style:const TextStyle(fontWeight:FontWeight.w500)),
        subtitle:Text(S.t('files.folderCount',{'n':_currentFiles.where((x)=>normalFolder(x.folder)==f||normalFolder(x.folder).startsWith('$f/')).length})),
        onTap:()=>_select(_personalTab,f),trailing:_folderMenu(f))))),
      for(final f in files)_draggable((file:f,folder:null,personal:_personalTab),icon:fileKind(f).icon,color:fileKind(f).color,label:f.name,child:ListTile(leading:_kindIcon(fileKind(f)),title:Text(f.name,maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text([if(showFolder&&normalFolder(f.folder).isNotEmpty)folderLabel(normalFolder(f.folder)),if(!_personalTab)f.senderId,_size(f.sizeBytes),_date(f.createdAt)].join(' · '),
          style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        onTap:()=>_open(f),trailing:_fileMenu(f))),
    ]);
  }

  static String _type(SarcadeSharedFile f){
    final i=f.name.lastIndexOf('.');
    return i<0||i==f.name.length-1?'—':f.name.substring(i+1).toUpperCase();
  }

  /// Details view (computer): Nom, Type, Taille, Modifié, sortable by a
  /// click on the header; folders first.
  Widget _details(List<String> folders,List<SarcadeSharedFile> files,{bool showFolder=false}){
    final t=Theme.of(context); final muted=t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant);
    final sorted=[...files]..sort((a,b){
      final c=switch(_sortBy){
        'type'=>_type(a).compareTo(_type(b)),
        'size'=>a.sizeBytes.compareTo(b.sizeBytes),
        'date'=>a.createdAt.compareTo(b.createdAt),
        _=>a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return _sortUp?c:-c;
    });
    final dirs=[...folders]; if(_sortBy=='name'&&!_sortUp)dirs.setAll(0,dirs.reversed.toList());
    Widget head(String key,String label,int flex,{TextAlign align=TextAlign.start}){
      final on=_sortBy==key;
      return Expanded(flex:flex,child:InkWell(onTap:()=>setState((){if(on){_sortUp=!_sortUp;}else{_sortBy=key;_sortUp=key!='date';}}),
        child:Padding(padding:const EdgeInsets.symmetric(vertical:8,horizontal:6),child:Row(
          mainAxisAlignment:align==TextAlign.end?MainAxisAlignment.end:MainAxisAlignment.start,children:[
          Flexible(child:Text(label,overflow:TextOverflow.ellipsis,style:t.textTheme.labelMedium?.copyWith(fontWeight:on?FontWeight.w700:FontWeight.w500))),
          if(on)Icon(_sortUp?Icons.arrow_upward:Icons.arrow_downward,size:14),
        ]))));
    }
    Widget row({required Widget icon,required String name,required String type,required String size,required String date,
        required VoidCallback onTap,Widget? menu,String? folder}){
      return InkWell(onTap:onTap,child:Container(
        decoration:BoxDecoration(border:Border(bottom:BorderSide(color:t.dividerColor.withValues(alpha:0.4)))),
        padding:const EdgeInsets.symmetric(horizontal:8),height:44,child:Row(children:[
          Expanded(flex:6,child:Row(children:[icon,const SizedBox(width:10),
            Expanded(child:Text(folder==null?name:'$name  ·  $folder',maxLines:1,overflow:TextOverflow.ellipsis))])),
          Expanded(flex:2,child:Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Text(type,style:muted,overflow:TextOverflow.ellipsis))),
          Expanded(flex:2,child:Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Text(size,style:muted,textAlign:TextAlign.end))),
          Expanded(flex:3,child:Padding(padding:const EdgeInsets.symmetric(horizontal:6),child:Text(date,style:muted,overflow:TextOverflow.ellipsis))),
          SizedBox(width:48,child:menu),
        ])));
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Container(padding:const EdgeInsets.symmetric(horizontal:8),
        decoration:BoxDecoration(border:Border(bottom:BorderSide(color:t.dividerColor))),
        child:Row(children:[
          head('name',S.t('files.colName'),6),head('type',S.t('files.colType'),2),
          head('size',S.t('files.colSize'),2,align:TextAlign.end),head('date',S.t('files.colDate'),3),
          const SizedBox(width:48),
        ])),
      Expanded(child:ListView(padding:const EdgeInsets.only(bottom:96),children:[
        for(final f in dirs)_target(f,(over)=>_hl(over,_draggable((file:null,folder:f,personal:_personalTab),icon:Icons.folder,color:folderColor,label:folderLabel(f),
          child:row(icon:const Icon(Icons.folder,color:folderColor,size:22),name:folderLabel(f),type:S.t('files.typeFolder'),
          size:S.t('files.folderCount',{'n':_currentFiles.where((x)=>normalFolder(x.folder)==f||normalFolder(x.folder).startsWith('$f/')).length}),date:'',
          onTap:()=>_select(_personalTab,f),menu:_folderMenu(f))))),
        for(final f in sorted)_draggable((file:f,folder:null,personal:_personalTab),icon:fileKind(f).icon,color:fileKind(f).color,label:f.name,
          child:row(icon:Icon(fileKind(f).icon,color:fileKind(f).color,size:22),name:f.name,type:_type(f),size:_size(f.sizeBytes),
          date:_date(f.createdAt),folder:showFolder&&normalFolder(f.folder).isNotEmpty?folderLabel(normalFolder(f.folder)):null,
          onTap:()=>_open(f),menu:_fileMenu(f))),
      ])),
    ]);
  }

  /// Opens a folder of a root (Événement or Personnel) and unfolds its parents.
  void _select(bool personal,String path){
    if(_tabs.index!=(personal?1:0))_tabs.index=personal?1:0;
    setState((){
      if(personal){_personalPath=path;}else{_eventPath=path;}
      var x=path; final r=personal?'p:':'e:';
      _expanded.add(r);
      while(x.isNotEmpty){_expanded.add('$r$x');x=parentFolder(x);}
    });
  }

  /// Folder tree (computer): the two roots, folders up to 3 levels, a
  /// chevron to unfold, the selected folder highlighted.
  Widget _tree(){
    final t=Theme.of(context); final s=t.colorScheme;
    final rows=<Widget>[];
    void node({required bool personal,required String path,required String label,required IconData icon,required Set<String> folders,int depth=0}){
      final key='${personal?'p:':'e:'}$path';
      final kids=childFolders(folders,path);
      final open=_expanded.contains(key);
      final selected=_tabs.index==(personal?1:0)&&(personal?_personalPath:_eventPath)==path;
      final same=_tabs.index==(personal?1:0);
      rows.add(!same?_treeRow(selected,s,personal,path,depth,kids,open,key,icon,label):_target(path,(over)=>_hl(over,_treeRow(selected,s,personal,path,depth,kids,open,key,icon,label))));
      if(open){for(final k in kids){node(personal:personal,path:k,label:folderLabel(k),icon:Icons.folder,folders:folders,depth:depth+1);}}
    }
    node(personal:false,path:'',label:S.t('files.tabEvent'),icon:Icons.groups_outlined,folders:_folders);
    if(_personal!=null){
      node(personal:true,path:'',label:S.t('files.tabPersonal'),icon:Icons.folder_shared_outlined,
        folders:allFolders(_personal!.folders,_personal!.files));
    }
    return ListView(padding:const EdgeInsets.all(8),children:rows);
  }

  Widget _treeRow(bool selected,ColorScheme s,bool personal,String path,int depth,List<String> kids,bool open,String key,IconData icon,String label){
      return Material(color:selected?s.primaryContainer.withValues(alpha:0.6):Colors.transparent,borderRadius:BorderRadius.circular(8),
        child:InkWell(borderRadius:BorderRadius.circular(8),onTap:()=>_select(personal,path),child:SizedBox(height:36,child:Row(children:[
          SizedBox(width:8.0+depth*16),
          SizedBox(width:24,child:kids.isEmpty?null:InkWell(customBorder:const CircleBorder(),
            onTap:()=>setState((){if(open){_expanded.remove(key);}else{_expanded.add(key);}}),
            child:Icon(open?Icons.expand_more:Icons.chevron_right,size:20,color:s.onSurfaceVariant))),
          Icon(icon,size:20,color:path.isEmpty?s.primary:folderColor),const SizedBox(width:8),
          Expanded(child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontWeight:selected||path.isEmpty?FontWeight.w600:FontWeight.w400))),
        ]))));
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
      if(_path.isNotEmpty)RoundIconButton(tooltip:S.t('files.up'),onPressed:()=>setState(()=>_path=parentFolder(_path)),icon:Icons.arrow_upward),
      // At the root, no breadcrumb: « Événement » / « Personnel » is already the
      // tab (charte, 30 Oct 2026, 10 h 46, rule 6).
      Expanded(child:_path.isEmpty?const SizedBox.shrink():SingleChildScrollView(scrollDirection:Axis.horizontal,reverse:true,child:Row(children:[
        for(var i=0;i<crumbs.length;i++)...[
          if(i>0)Icon(Icons.chevron_right,size:18,color:t.colorScheme.onSurfaceVariant),
          if(i<crumbs.length-1)_target(crumbs[i].path,(over)=>_hl(over,TextButton(onPressed:()=>setState(()=>_path=crumbs[i].path),
            style:TextButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:6)),
            child:Text(crumbs[i].label,style:const TextStyle(fontWeight:FontWeight.w500)))))
          else TextButton(onPressed:null,
            style:TextButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:6),disabledForegroundColor:t.colorScheme.onSurface),
            child:Text(crumbs[i].label,style:TextStyle(fontWeight:i==crumbs.length-1?FontWeight.w700:FontWeight.w500))),
        ],
      ]))),
      RoundIconButton(tooltip:S.t(_grid?'files.asList':'files.asGrid'),onPressed:() async {await widget.store?.setPreference('files_grid',_grid?null:'1');if(mounted)setState((){});},
        icon:_grid?Icons.view_list_outlined:Icons.grid_view_outlined),
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
    if(_error!=null){
      return Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(S.t('event.offline')),OutlinedButton(onPressed:_load,child:Text(S.t('common.retry')))])));
    }
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
      if(!searching&&_eventPath.isEmpty&&widget.drawings!=null&&canManageDrawings(widget.actorId))DrawingsSection(actions:widget.drawings!,onDone:_load),
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
    return LayoutBuilder(builder:(context,c){
      _wide=c.maxWidth>=760;
      final help=Padding(padding:const EdgeInsets.fromLTRB(16,4,16,4),child:Text(S.t(_personalTab?'files.personalHelpShort':'files.eventHelpShort'),
        maxLines:1,overflow:TextOverflow.ellipsis,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant)));
      final actions=[?_quota(),
        IconButton(tooltip:S.t('routes.refresh'),onPressed:(){_load();_loadPersonal();},icon:const Icon(Icons.refresh))];
      if(_wide){
        return Scaffold(
          appBar:LinkedAppBar(title:Text(S.t('map.files')),actions:actions,bottom:PreferredSize(preferredSize:const Size.fromHeight(26),child:help)),
          body:Row(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            SizedBox(width:260,child:_tree()),
            const VerticalDivider(width:1),
            Expanded(child:_personalTab?_personalTabView():_eventTab()),
          ]));
      }
      return Scaffold(
        appBar:LinkedAppBar(title:Text(S.t('map.files')),actions:actions,
          bottom:PreferredSize(preferredSize:const Size.fromHeight(70),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            // Tabs on the left, underlined (not spread over the whole width).
            TabBar(controller:_tabs,isScrollable:true,tabAlignment:TabAlignment.start,tabs:[Tab(text:S.t('files.tabEvent')),Tab(text:S.t('files.tabPersonal'))]),
            help,
          ]))),
        body:TabBarView(controller:_tabs,children:[_eventTab(),_personalTabView()]),
      );
    });
  }
}

/// What is dragged: a file or a folder, of the Événement or Personnel root.
typedef _Drag=({SarcadeSharedFile? file,String? folder,bool personal});
