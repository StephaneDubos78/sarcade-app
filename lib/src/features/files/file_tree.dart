/// Folders of the Files screen (« Fichiers : sous-dossiers », validated on
/// 29 Oct 2026): up to 3 levels, « A/B/C » paths, "" for the root. Pure code.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/shared_file.dart';

const maxFolderDepth=3;

/// The fixed folders of before (« divers ») now live at the root.
String normalFolder(String f)=>f=='divers'?'':f;

int folderDepth(String path)=>path.isEmpty?0:path.split('/').length;
String folderName(String path)=>path.isEmpty?'':path.split('/').last;
String parentFolder(String path){final i=path.lastIndexOf('/');return i<0?'':path.substring(0,i);}
String joinFolder(String parent,String name)=>parent.isEmpty?name:'$parent/$name';

/// Shown name of a folder: the old fixed folders keep their translation.
String folderLabel(String path){
  final n=folderName(path);
  return fileFolders.contains(n)&&!path.contains('/')?S.t('files.folder.$n'):n;
}

/// Every known folder, the parents included, and those implied by files.
Set<String> allFolders(Iterable<String> folders,Iterable<SarcadeSharedFile> files){
  final out=<String>{};
  void add(String p){var x=normalFolder(p);while(x.isNotEmpty){out.add(x);x=parentFolder(x);}}
  for(final f in folders){add(f);}
  for(final f in files){add(f.folder);}
  return out;
}

/// Sub-folders directly in [parent], sorted by name.
List<String> childFolders(Iterable<String> folders,String parent)=>
  (folders.where((f)=>f.isNotEmpty&&parentFolder(f)==parent).toList()..sort((a,b)=>folderLabel(a).toLowerCase().compareTo(folderLabel(b).toLowerCase())));

/// Files directly in [folder], most recent first.
List<SarcadeSharedFile> filesIn(Iterable<SarcadeSharedFile> files,String folder)=>
  (files.where((f)=>normalFolder(f.folder)==folder).toList()..sort((a,b)=>b.createdAt.compareTo(a.createdAt)));

/// « Personnel › Procédures › Radio »: each step and its path.
List<({String label,String path})> breadcrumb(String root,String path){
  final out=[(label:root,path:'')];
  var acc='';
  for(final part in path.isEmpty?const <String>[]:path.split('/')){acc=joinFolder(acc,part);out.add((label:folderLabel(acc),path:acc));}
  return out;
}

/// Name typed for a folder: 1 to 60 characters, no slash.
String? validFolderName(String v){
  final t=v.trim();
  if(t.isEmpty||t.length>60||t=='.'||t=='..'||t.contains('/')||t.contains('\\'))return null;
  return t;
}

/// Coloured icon by type: PDF red, image green, text blue, map orange.
({IconData icon,Color color}) fileKind(SarcadeSharedFile f){
  final n=f.name.toLowerCase(); final m=f.mimeType;
  if(m=='application/pdf'||n.endsWith('.pdf'))return (icon:Icons.picture_as_pdf,color:const Color(0xFFD93025));
  if(f.isImage)return (icon:Icons.image,color:const Color(0xFF188038));
  if(n.endsWith('.gpx')||n.endsWith('.kml')||n.endsWith('.kmz')||n.endsWith('.geojson'))return (icon:Icons.map,color:const Color(0xFFE8710A));
  if(m.startsWith('text/')||n.endsWith('.txt')||n.endsWith('.doc')||n.endsWith('.docx')||n.endsWith('.odt')||n.endsWith('.md')){
    return (icon:Icons.description,color:const Color(0xFF1A73E8));
  }
  return (icon:Icons.insert_drive_file,color:const Color(0xFF5F6368));
}
const folderColor=Color(0xFFF9AB00);
