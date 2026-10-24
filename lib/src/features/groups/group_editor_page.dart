import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart';

/// Result of the editor: the group to save, or a deletion.
class GroupEdit {
  final CommGroup group; final bool deleted;
  const GroupEdit(this.group,{this.deleted=false});
}

const groupColors=[0xFF546E7A,0xFFC62828,0xFF6A1B9A,0xFF2E7D32,0xFF1565C0,0xFFEF6C00,0xFF00897B,0xFF5D4037];

/// Creation or change of a communication group. Every operator creates a
/// group and becomes its manager; then only managers and the PCO change it.
class GroupEditorPage extends StatefulWidget {
  final String eventId, actorId; final CommGroup? initial;
  const GroupEditorPage({super.key,required this.eventId,required this.actorId,this.initial});
  @override State<GroupEditorPage> createState()=>_GroupEditorPageState();
}

class _GroupEditorPageState extends State<GroupEditorPage> {
  final _form=GlobalKey<FormState>();
  late final _name=TextEditingController(text:widget.initial?.name??'');
  late final _description=TextEditingController(text:widget.initial?.description??'');
  late final _members=TextEditingController(text:(widget.initial?.members??const []).join(', '));
  late final _senders=TextEditingController(text:(widget.initial?.senders??const []).join(', '));
  late final _radio=TextEditingController(text:widget.initial?.radioChannel??'');
  late bool _listenOnly=widget.initial?.listenOnly??false;
  late bool _archived=widget.initial?.archived??false;
  late int _color=widget.initial?.color??groupColors.first;

  @override void dispose(){for(final c in [_name,_description,_members,_senders,_radio]){c.dispose();}super.dispose();}

  void _save(){
    if(!_form.currentState!.validate())return;
    final now=DateTime.now().toUtc();
    final initial=widget.initial;
    final group=initial==null
      ? CommGroup(id:const Uuid().v4(),eventId:widget.eventId,name:_name.text.trim(),description:_description.text.trim(),
          mode:_listenOnly?'listen_only':'discussion',kind:'custom',createdBy:widget.actorId,updatedBy:widget.actorId,
          radioChannel:_radio.text.trim(),color:_color,members:parseIds(_members.text),senders:parseIds(_senders.text),
          managers:[widget.actorId],updatedAt:now)
      : initial.copyWith(name:_name.text.trim(),description:_description.text.trim(),mode:_listenOnly?'listen_only':'discussion',
          color:_color,archived:_archived,members:parseIds(_members.text),senders:parseIds(_senders.text),
          radioChannel:_radio.text.trim(),updatedBy:widget.actorId,updatedAt:now);
    Navigator.pop(context,GroupEdit(group));
  }

  Future<void> _delete() async {
    final g=widget.initial!;
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      content:Text(S.t('groups.deleteConfirm',{'name':g.name})),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.ok')))],
    ));
    if(ok==true&&mounted)Navigator.pop(context,GroupEdit(g,deleted:true));
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.initial==null?S.t('groups.new'):S.t('groups.edit')),actions:[
      if(widget.initial!=null)IconButton(tooltip:S.t('groups.delete'),onPressed:_delete,icon:const Icon(Icons.delete_outline)),
    ]),
    body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:Form(key:_form,child:ListView(padding:const EdgeInsets.all(20),children:[
      TextFormField(controller:_name,maxLength:80,decoration:InputDecoration(labelText:S.t('groups.name'),border:const OutlineInputBorder()),
        validator:(v)=>(v==null||v.trim().isEmpty)?S.t('settings.required'):null),
      const SizedBox(height:12),
      TextFormField(controller:_description,maxLength:300,maxLines:2,decoration:InputDecoration(labelText:S.t('groups.description'),border:const OutlineInputBorder())),
      const SizedBox(height:12),
      TextFormField(controller:_members,decoration:InputDecoration(labelText:S.t('groups.members'),border:const OutlineInputBorder())),
      SwitchListTile(contentPadding:EdgeInsets.zero,value:_listenOnly,onChanged:(v)=>setState(()=>_listenOnly=v),
        title:Text(S.t('groups.listenOnly')),subtitle:Text(S.t('groups.listenOnlyHelp'))),
      if(_listenOnly)TextFormField(controller:_senders,decoration:InputDecoration(labelText:S.t('groups.senders'),border:const OutlineInputBorder())),
      const SizedBox(height:12),
      TextFormField(controller:_radio,maxLength:80,decoration:InputDecoration(labelText:S.t('groups.radio'),border:const OutlineInputBorder())),
      const SizedBox(height:8),
      Text(S.t('groups.color')),
      const SizedBox(height:6),
      Wrap(spacing:8,children:[for(final c in groupColors)GestureDetector(
        onTap:()=>setState(()=>_color=c),
        child:CircleAvatar(radius:16,backgroundColor:Color(c),child:_color==c?const Icon(Icons.check,color:Colors.white,size:18):null),
      )]),
      if(widget.initial!=null)SwitchListTile(contentPadding:EdgeInsets.zero,value:_archived,onChanged:(v)=>setState(()=>_archived=v),
        title:Text(S.t('groups.archived'))),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:_save,icon:const Icon(Icons.check),label:Text(S.t('common.save'))),
    ]))))),
  );
}
