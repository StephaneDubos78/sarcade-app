/// Bottom save bar (charte « style Play Console », validated on 29 Oct
/// 2026): a thin line above, « Annuler » and « Enregistrer » as pills aligned
/// on the right, « Enregistrer » greyed while nothing has changed. The rule
/// for every screen that saves or validates.
library;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';

class SaveBar extends StatelessWidget {
  final bool changed, saving;
  final VoidCallback? onCancel;
  final VoidCallback onSave;
  final String? saveLabel;
  const SaveBar({super.key,required this.changed,required this.onSave,this.onCancel,this.saving=false,this.saveLabel});

  @override
  Widget build(BuildContext context){
    final s=Theme.of(context).colorScheme;
    return Material(color:s.surface,child:SafeArea(top:false,child:Container(
      decoration:BoxDecoration(border:Border(top:BorderSide(color:s.outlineVariant))),
      padding:const EdgeInsets.fromLTRB(16,10,16,10),
      child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[
        if(onCancel!=null)OutlinedButton(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
          onPressed:changed&&!saving?onCancel:null,child:Text(S.t('common.cancel'))),
        const SizedBox(width:10),
        FilledButton(style:FilledButton.styleFrom(shape:const StadiumBorder(),padding:const EdgeInsets.symmetric(horizontal:22)),
          onPressed:changed&&!saving?onSave:null,
          child:saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):Text(saveLabel??S.t('common.save'))),
      ]))));
  }
}
