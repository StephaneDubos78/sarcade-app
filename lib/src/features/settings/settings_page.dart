import 'package:flutter/material.dart';
import '../../config/app_config.dart';

/// Operator settings: server address, event and terminal identifier.
/// Lets one APK serve every field operator instead of one build per terminal.
class SettingsPage extends StatefulWidget {
  final AppConfig initial;
  final Future<void> Function(AppConfig) onSave;
  final bool firstRun;
  const SettingsPage({super.key,required this.initial,required this.onSave,this.firstRun=false});
  @override State<SettingsPage> createState()=>_SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form=GlobalKey<FormState>();
  late final TextEditingController _server=TextEditingController(text:widget.initial.serverUrl);
  late final TextEditingController _event=TextEditingController(text:widget.initial.eventId);
  late final TextEditingController _device=TextEditingController(text:widget.initial.deviceId);
  bool _saving=false;

  @override void dispose(){_server.dispose();_event.dispose();_device.dispose();super.dispose();}

  String? _required(String? v)=>(v==null||v.trim().isEmpty)?'Champ obligatoire':null;

  String? _url(String? v){
    final r=_required(v);
    if(r!=null)return r;
    final u=Uri.tryParse(v!.trim());
    if(u==null||!(u.scheme=='http'||u.scheme=='https')||u.host.isEmpty)return 'Adresse attendue : http://IP:8000';
    return null;
  }

  Future<void> _save() async {
    if(!_form.currentState!.validate())return;
    setState(()=>_saving=true);
    var server=_server.text.trim();
    while(server.endsWith('/')){server=server.substring(0,server.length-1);}
    await widget.onSave(widget.initial.copyWith(serverUrl:server,eventId:_event.text.trim(),deviceId:_device.text.trim()));
    if(mounted)setState(()=>_saving=false);
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.firstRun?'Configuration SARCADE':'Paramètres'),automaticallyImplyLeading:!widget.firstRun),
    body:SafeArea(child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:560),
      child:Form(key:_form,child:ListView(padding:const EdgeInsets.all(20),children:[
        if(widget.firstRun)...[
          Text('Avant de commencer, indique le serveur SARCADE et ton identifiant pour cet événement.',style:Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height:20),
        ],
        TextFormField(
          controller:_server,
          decoration:const InputDecoration(labelText:'Serveur',hintText:'http://192.168.1.20:8000',helperText:'Adresse du serveur sur le réseau local, pas localhost',border:OutlineInputBorder()),
          keyboardType:TextInputType.url,autocorrect:false,validator:_url,
        ),
        const SizedBox(height:16),
        TextFormField(
          controller:_event,
          decoration:const InputDecoration(labelText:'Événement',border:OutlineInputBorder()),
          autocorrect:false,validator:_required,
        ),
        const SizedBox(height:16),
        TextFormField(
          controller:_device,
          decoration:const InputDecoration(labelText:'Identifiant du terminal',hintText:'TERRAIN-01',helperText:'Unique par opérateur, affiché sur la carte du PCO',border:OutlineInputBorder()),
          autocorrect:false,validator:_required,
        ),
        const SizedBox(height:24),
        FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.check),label:const Text('Enregistrer')),
      ])),
    ))),
  );
}
