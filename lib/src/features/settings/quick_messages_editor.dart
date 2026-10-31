import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../ui/link_status.dart';

/// Usual predefined messages, offered when the event has none of its own.
List<String> defaultQuickMessages()=>[for(final k in const ['inPlace','signalHeard','signalLost','backToPco','needHelp','copy'])S.t('quick.$k')];

/// Cleaned list as sent to the server: trimmed, no empty line, 20 at most.
List<String> cleanQuickMessages(Iterable<String> list)=>list.map((l)=>l.trim()).where((l)=>l.isNotEmpty).take(maxQuickMessages).toList();
const maxQuickMessages=20;

/// Paramètres › Événement › Messages prédéfinis (decision of 29 Oct 2026,
/// option A): a list, each message edited in place, deleted, reordered by
/// drag and drop, « + Ajouter » at the bottom. Returns the list to save, or
/// null when cancelled.
class QuickMessagesEditor extends StatefulWidget {
  final List<String> initial;
  const QuickMessagesEditor({super.key,required this.initial});
  @override State<QuickMessagesEditor> createState()=>_QuickMessagesEditorState();
}

class _QuickMessagesEditorState extends State<QuickMessagesEditor> {
  int _next=0;
  late final List<(int,TextEditingController)> _rows=[
    for(final t in widget.initial.isEmpty?defaultQuickMessages():widget.initial)(_next++,TextEditingController(text:t))];
  late final bool _fromDefaults=widget.initial.isEmpty;
  final _focus=<int,FocusNode>{};

  @override void dispose(){for(final r in _rows){r.$2.dispose();}for(final f in _focus.values){f.dispose();}super.dispose();}

  void _add(){
    if(_rows.length>=maxQuickMessages)return;
    final id=_next++;
    final f=_focus[id]=FocusNode();
    setState(()=>_rows.add((id,TextEditingController())));
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)f.requestFocus();});
  }
  void _remove(int i){final r=_rows.removeAt(i);setState((){});WidgetsBinding.instance.addPostFrameCallback((_){r.$2.dispose();_focus.remove(r.$1)?.dispose();});}

  @override Widget build(BuildContext context){
    final t=Theme.of(context);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('event.quick')),actions:[
        TextButton(onPressed:()=>Navigator.pop(context,cleanQuickMessages(_rows.map((r)=>r.$2.text))),child:Text(S.t('common.save'))),
      ]),
      body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,4),child:Text(S.t('event.quickIntro'),style:t.textTheme.bodyMedium)),
        if(_fromDefaults)Padding(padding:const EdgeInsets.fromLTRB(16,0,16,4),
          child:Text(S.t('event.quickDefaults'),style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant))),
        Expanded(child:ReorderableListView.builder(
          buildDefaultDragHandles:false,
          padding:const EdgeInsets.only(bottom:8),
          itemCount:_rows.length,
          onReorderItem:(a,b){setState(()=>_rows.insert(b,_rows.removeAt(a)));},
          itemBuilder:(c,i){
            final r=_rows[i];
            return ListTile(key:ValueKey(r.$1),
              leading:ReorderableDragStartListener(index:i,child:Tooltip(message:S.t('event.quickMove'),child:const Icon(Icons.drag_handle))),
              title:TextField(controller:r.$2,focusNode:_focus[r.$1],maxLength:200,textCapitalization:TextCapitalization.sentences,
                decoration:InputDecoration(isDense:true,counterText:'',hintText:S.t('event.quickHint'))),
              trailing:IconButton(tooltip:S.t('common.delete'),icon:const Icon(Icons.delete_outline),onPressed:()=>_remove(i)));
          })),
        SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Row(children:[
          FilledButton.icon(onPressed:_rows.length>=maxQuickMessages?null:_add,icon:const Icon(Icons.add),label:Text(S.t('event.quickAdd'))),
          const SizedBox(width:12),
          Text(S.t('event.quickCount',{'n':_rows.length,'max':maxQuickMessages}),style:t.textTheme.bodySmall),
        ]))),
      ]),
    );
  }
}
