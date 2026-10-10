import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../../operations/event_settings.dart';
import '../../services/notification_service.dart';

/// Operator settings: server address, event and terminal identifier,
/// language, radio callsign. Lets one APK serve every field operator
/// instead of one build per terminal.
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
  late final TextEditingController _callsign=TextEditingController(text:widget.initial.callsign);
  late String _language=widget.initial.language;
  late bool _aprsConsent=widget.initial.aprsTxConsent;
  late bool _bypassDnd=widget.initial.immediateBypassDnd;
  bool _saving=false;

  @override void dispose(){_server.dispose();_event.dispose();_device.dispose();_callsign.dispose();super.dispose();}

  String? _required(String? v)=>(v==null||v.trim().isEmpty)?S.t('settings.required'):null;

  String? _url(String? v){
    final r=_required(v);
    if(r!=null)return r;
    final u=Uri.tryParse(v!.trim());
    if(u==null||!(u.scheme=='http'||u.scheme=='https')||u.host.isEmpty)return S.t('settings.urlExpected');
    return null;
  }

  String? _callsignCheck(String? v)=>(v==null||v.trim().isEmpty||validCallsign(v))?null:S.t('settings.callsignInvalid');

  Future<void> _save() async {
    if(!_form.currentState!.validate())return;
    setState(()=>_saving=true);
    var server=_server.text.trim();
    while(server.endsWith('/')){server=server.substring(0,server.length-1);}
    await widget.onSave(widget.initial.copyWith(serverUrl:server,eventId:_event.text.trim(),deviceId:_device.text.trim(),
      language:_language,callsign:_callsign.text.trim().toUpperCase(),aprsTxConsent:_aprsConsent,
      immediateBypassDnd:_bypassDnd));
    if(mounted)setState(()=>_saving=false);
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.firstRun?S.t('settings.firstRun'):S.t('settings.title')),automaticallyImplyLeading:!widget.firstRun),
    body:SafeArea(child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:560),
      child:Form(key:_form,child:ListView(padding:const EdgeInsets.all(20),children:[
        if(widget.firstRun)...[
          Text(S.t('settings.intro'),style:Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height:20),
        ],
        TextFormField(
          controller:_server,
          decoration:InputDecoration(labelText:S.t('settings.server'),hintText:'http://192.168.1.20:8000',helperText:S.t('settings.serverHelp'),border:const OutlineInputBorder()),
          keyboardType:TextInputType.url,autocorrect:false,validator:_url,
        ),
        const SizedBox(height:16),
        TextFormField(
          controller:_event,
          decoration:InputDecoration(labelText:S.t('settings.event'),border:const OutlineInputBorder()),
          autocorrect:false,validator:_required,
        ),
        const SizedBox(height:16),
        TextFormField(
          controller:_device,
          decoration:InputDecoration(labelText:S.t('settings.device'),hintText:'TERRAIN-01',helperText:S.t('settings.deviceHelp'),border:const OutlineInputBorder()),
          autocorrect:false,validator:_required,
        ),
        const SizedBox(height:16),
        DropdownButtonFormField<String>(
          initialValue:_language,
          decoration:InputDecoration(labelText:S.t('settings.language'),border:const OutlineInputBorder()),
          items:[
            DropdownMenuItem(value:'system',child:Text(S.t('settings.languageSystem'))),
            const DropdownMenuItem(value:'fr',child:Text('Français')),
            const DropdownMenuItem(value:'en',child:Text('English')),
          ],
          onChanged:(v)=>setState(()=>_language=v??'system'),
        ),
        const SizedBox(height:16),
        TextFormField(
          controller:_callsign,
          decoration:InputDecoration(labelText:S.t('settings.callsign'),hintText:'F4ABC-7',helperText:S.t('settings.callsignHelp'),border:const OutlineInputBorder()),
          autocorrect:false,textCapitalization:TextCapitalization.characters,validator:_callsignCheck,
        ),
        SwitchListTile(
          contentPadding:EdgeInsets.zero,
          value:_aprsConsent,onChanged:(v)=>setState(()=>_aprsConsent=v),
          title:Text(S.t('settings.aprsConsent')),subtitle:Text(S.t('settings.aprsConsentHelp')),
        ),
        if(NotificationService.supportsDndBypass)SwitchListTile(
          contentPadding:EdgeInsets.zero,
          value:_bypassDnd,
          onChanged:(v) async {
            setState(()=>_bypassDnd=v);
            if(!v)return;
            final granted=await NotificationService().enableDndBypass();
            if(!granted&&context.mounted){
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('settings.dndPending'))));
            }
          },
          title:Text(S.t('settings.dndBypass')),subtitle:Text(S.t('settings.dndBypassHelp')),
        ),
        const SizedBox(height:24),
        FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.check),label:Text(S.t('common.save'))),
        const SizedBox(height:16),
        Text('SARCADE $appVersion',textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodySmall),
      ])),
    ))),
  );
}
