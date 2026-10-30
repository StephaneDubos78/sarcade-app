import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco, myRoles;

/// Import and export of the event's drawings, moved from the drawing toolbar
/// to Plus › Fichiers (card « Barre de dessin, boutons Import et Export JSON
/// à déplacer », validated 30 Oct 2026, 13 h 27), PCO and admin only.
class DrawingFileActions {
  final Future<void> Function() importFile, exportAll;
  /// Number of drawn objects (export disabled without any).
  final int Function() count;
  const DrawingFileActions({required this.importFile,required this.exportAll,required this.count});
}

bool canManageDrawings(String actorId)=>isPco(actorId)||myRoles.contains('admin');

/// Rubrique « Dessins de l'événement » of the Événement tab.
class DrawingsSection extends StatelessWidget {
  final DrawingFileActions actions; final VoidCallback? onDone;
  const DrawingsSection({super.key,required this.actions,this.onDone});
  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    final empty=actions.count()==0;
    return Padding(padding:const EdgeInsets.fromLTRB(12,8,12,0),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(S.t('files.drawings'),style:t.textTheme.titleSmall),
      const SizedBox(height:6),
      Wrap(spacing:8,runSpacing:8,children:[
        Tooltip(message:S.t('files.importDrawingsHelp'),child:OutlinedButton.icon(key:const ValueKey('drawings-import'),onPressed:() async {await actions.importFile();onDone?.call();},
          icon:const Icon(Icons.file_upload_outlined),label:Text(S.t('files.importDrawings')))),
        OutlinedButton.icon(key:const ValueKey('drawings-export'),onPressed:empty?null:() async {await actions.exportAll();onDone?.call();},
          icon:const Icon(Icons.file_download_outlined),label:Text(S.t('files.exportDrawings'))),
      ]),
    ]));
  }
}
