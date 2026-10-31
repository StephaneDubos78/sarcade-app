/// Default frequencies of the bearing tool, edited by the administrator
/// (Paramètres › Événement): add, hide, reorder, delete. Saved on the server
/// for every operator.
library;

import '../../ui/choice_pills.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';
import '../../ui/save_bar.dart';
import 'signals.dart';
import '../../ui/link_status.dart';

class SignalDefaultsPage extends StatefulWidget {
  final SarcadeApi api; final LocalStore? store;
  const SignalDefaultsPage({super.key,required this.api,this.store});
  @override State<SignalDefaultsPage> createState()=>_SignalDefaultsPageState();
}

class _SignalDefaultsPageState extends State<SignalDefaultsPage> {
  List<SignalChoice> _list=[...defaultSignals];
  bool _loading=true, _saving=false, _changed=false;
  String? _error;

  @override void initState(){super.initState();_load();}

  Future<void> _load() async {
    try{
      final body=await widget.api.signalDefaults();
      _list=decodeSignals(body);
    }catch(_){_error=S.t('signals.loadError');}
    if(mounted)setState(()=>_loading=false);
  }

  Future<void> _save() async {
    setState(()=>_saving=true);
    try{
      final body=encodeSignals(_list);
      await widget.api.saveSignalDefaults(body);
      await widget.store?.setPreference('signal_defaults',body);
      if(!mounted)return;
      setState((){_changed=false;_saving=false;});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('signals.saved'))));
    }on SarcadeHttpException catch(e){
      if(!mounted)return;
      setState(()=>_saving=false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(e.statusCode==403?'signals.forbidden':'signals.saveError'))));
    }catch(_){
      if(!mounted)return;
      setState(()=>_saving=false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('signals.saveError'))));
    }
  }

  Future<void> _edit({int? index}) async {
    final old=index==null?null:_list[index];
    final f=TextEditingController(text:old?.frequencyMhz==null?'':old!.frequencyMhz!.toStringAsFixed(3).replaceAll('.',','));
    final l=TextEditingController(text:old?.label??'');
    var exercise=old?.exercise??false;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(
      title:Text(S.t(old==null?'signals.add':'signals.edit')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(controller:f,autofocus:true,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:InputDecoration(labelText:S.t('bearings.signalFreq'),suffixText:'MHz')),
        const SizedBox(height:8),
        TextField(controller:l,maxLength:60,decoration:InputDecoration(labelText:S.t('bearings.signalLabel'))),
        ChoicePills<bool>(choices:[(value:false,label:S.t('bearings.signalReal'),icon:null),(value:true,label:S.t('bearings.signalExercise'),icon:null)],
          selected:exercise,onSelected:(v)=>set(()=>exercise=v)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('common.ok')))])));
    final freq=parseMhz(f.text), label=l.text.trim();
    f.dispose(); l.dispose();
    if(ok!=true)return;
    if(freq==null||label.isEmpty){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('signals.invalid'))));
      return;
    }
    final s=SignalChoice(label:label,frequencyMhz:freq,exercise:exercise,hidden:old?.hidden??false);
    setState((){if(index==null){_list.add(s);}else{_list[index]=s;}_changed=true;});
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('signals.title'))),
      floatingActionButton:_loading||_list.length>=20?null:FloatingActionButton.extended(onPressed:()=>_edit(),
        icon:const Icon(Icons.add),label:Text(S.t('signals.add'))),
      body:_loading?const Center(child:CircularProgressIndicator()):Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.fromLTRB(20,12,20,8),child:Text(_error??S.t('signals.help'),style:t.textTheme.bodyMedium?.copyWith(color:t.colorScheme.onSurfaceVariant))),
        Expanded(child:ReorderableListView(
          padding:const EdgeInsets.only(bottom:96),
          onReorderItem:(a,b){setState((){final s=_list.removeAt(a);_list.insert(b,s);_changed=true;});},
          children:[for(var i=0;i<_list.length;i++)ListTile(key:ValueKey('sig-$i-${_list[i].name}'),
            leading:Icon(Icons.radio,color:_list[i].hidden?t.disabledColor:t.colorScheme.primary),
            title:Row(children:[Flexible(child:Text(_list[i].name,overflow:TextOverflow.ellipsis,
              style:TextStyle(color:_list[i].hidden?t.disabledColor:null))),if(_list[i].exercise)...[const SizedBox(width:6),const ExerciseBadge()]]),
            subtitle:_list[i].hidden?Text(S.t('signals.hidden')):null,
            onTap:()=>_edit(index:i),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              IconButton(tooltip:S.t(_list[i].hidden?'signals.show':'signals.hide'),
                onPressed:()=>setState((){_list[i]=_list[i].copyWith(hidden:!_list[i].hidden);_changed=true;}),
                icon:Icon(_list[i].hidden?Icons.visibility_off_outlined:Icons.visibility_outlined)),
              IconButton(tooltip:S.t('common.delete'),onPressed:()=>setState((){_list.removeAt(i);_changed=true;}),icon:const Icon(Icons.delete_outline)),
              const SizedBox(width:24),
            ]))],
        )),
        SaveBar(changed:_changed,saving:_saving,onCancel:(){setState((){_loading=true;_changed=false;});_load();},onSave:_save),
      ]),
    );
  }
}
