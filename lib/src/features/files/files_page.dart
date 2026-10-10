import '../../l10n/strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../platform/platform_services.dart';
import '../../models/shared_file.dart';
import '../../services/sarcade_api.dart';

class FilesPage extends StatefulWidget {
  final SarcadeApi api; final String eventId,actorId;
  const FilesPage({super.key,required this.api,required this.eventId,required this.actorId});
  @override State<FilesPage> createState()=>_FilesPageState();
}
class _FilesPageState extends State<FilesPage>{
  List<SarcadeSharedFile> files=[]; bool loading=true,uploading=false; String? error;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {try{files=await widget.api.files(widget.eventId);error=null;}catch(e){error='$e';}finally{if(mounted)setState(()=>loading=false);}}
  Future<void> _upload() async {
    final picked=await FilePicker.platform.pickFiles(withData:true);
    if(picked==null)return; final f=picked.files.single;
    final bytes=await readPickedFile(f);
    if(bytes==null)return;
    if(bytes.length>25*1024*1024){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.tooLarge'))));return;}
    setState(()=>uploading=true);
    try{await widget.api.uploadFile(widget.eventId,widget.actorId,f.name,'application/octet-stream',bytes);await _load();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.uploadFailed',{'error':e}))));}
    finally{if(mounted)setState(()=>uploading=false);}
  }
  Future<void> _open(SarcadeSharedFile f) async {
    try{
      final bytes=await widget.api.downloadFile(widget.eventId,f.id);
      // Installed apps open the file; the web app hands it to the browser as a download.
      final path=await saveFile(f.name,bytes,temporary:true,mimeType:f.mimeType);
      if(canOpenSavedFiles)await openSavedFile(path);
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('files.downloadFailed',{'error':e}))));}
  }
  String _size(int n)=>n<1024?'$n o':n<1024*1024?'${(n/1024).toStringAsFixed(1)} Ko':'${(n/1024/1024).toStringAsFixed(1)} Mo';
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(S.t('map.files')),actions:[IconButton(tooltip:S.t('routes.refresh'),onPressed:_load,icon:const Icon(Icons.refresh))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:uploading?null:_upload,icon:uploading?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.upload_file),label:Text(uploading?S.t('files.uploading'):S.t('files.upload'))),
    body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Text(error!)):files.isEmpty?Center(child:Text(S.t('files.none'))):ListView.builder(itemCount:files.length,itemBuilder:(c,i){final f=files[i];return ListTile(leading:const Icon(Icons.insert_drive_file_outlined),title:Text(f.name),subtitle:Text('${f.senderId} · ${_size(f.sizeBytes)} · ${f.createdAt.toLocal()}'),trailing:IconButton(icon:const Icon(Icons.download),onPressed:()=>_open(f)),onTap:()=>_open(f));}),
  );
}
