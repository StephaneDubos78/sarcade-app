import 'package:flutter/material.dart';
import '../../access/access_login_page.dart';
import '../../access/access_manager.dart';
import '../../access/access_session.dart';
import '../../config/app_config.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../../offline/outbox_policy.dart' show normalServer;
import '../../operations/event_settings.dart';
import '../../services/sarcade_api.dart' show SarcadeHttpException;

/// Operator settings: server address, event and terminal identifier,
/// language, radio callsign. Lets one APK serve every field operator
/// instead of one build per terminal.
class SettingsPage extends StatefulWidget {
  final AppConfig initial;
  final Future<void> Function(AppConfig) onSave;
  final bool firstRun;
  /// Events of a server (« Choix de l'événement dans une liste »): fetched
  /// list, and the last list known for offline use.
  final Future<List<Map<String,dynamic>>> Function(String server)? loadEvents;
  final List<Map<String,dynamic>> Function(String server)? cachedEvents;
  /// Items still waiting for a server and event, and « Envoyer d'abord »
  /// returning what is left (« Robustesse de la synchronisation »).
  final int Function(String server,String eventId)? waitingFor;
  final Future<int> Function(String server,String eventId)? sendFirst;
  const SettingsPage({super.key,required this.initial,required this.onSave,this.firstRun=false,
    this.loadEvents,this.cachedEvents,this.waitingFor,this.sendFirst});
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
  bool _saving=false;
  List<Map<String,dynamic>> _events=[];
  bool _loadingEvents=false, _eventsOffline=false, _accessRequired=false;
  String? _eventsError;

  @override void initState(){
    super.initState();
    _events=widget.cachedEvents?.call(_serverText)??[];
    if(widget.loadEvents!=null)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_loadEvents();});
  }

  @override void dispose(){_server.dispose();_event.dispose();_device.dispose();_callsign.dispose();super.dispose();}

  String get _serverText{var s=_server.text.trim();while(s.endsWith('/')){s=s.substring(0,s.length-1);}return s;}

  Future<void> _loadEvents() async {
    final load=widget.loadEvents;
    if(load==null||_url(_server.text)!=null)return;
    final server=_serverText;
    setState((){_loadingEvents=true;_eventsError=null;});
    try{
      final list=await load(server);
      if(!mounted||server!=_serverText)return;
      setState((){_events=list;_eventsOffline=false;_accessRequired=false;});
    }on AccessRequiredException{
      // Protected by Cloudflare Access: sign in first, then the list comes.
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_accessRequired=true;});
    }on SarcadeHttpException catch(e){
      // An older server without the list: the advanced entry stays available.
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_eventsError='HTTP ${e.statusCode}';});
    }catch(_){
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_eventsOffline=true;});
    }finally{
      if(mounted)setState(()=>_loadingEvents=false);
    }
  }

  Future<void> _signIn() async {
    if(_url(_server.text)!=null)return;
    if(await signInToServer(context,_serverText)&&mounted){setState(()=>_accessRequired=false);_loadEvents();}
  }

  /// Sign-in state of the server (Cloudflare Access), with its buttons.
  Widget _accessRow(){
    if(_url(_server.text)!=null)return const SizedBox.shrink();
    final server=_serverText;
    final session=AccessManager.instance.sessionFor(server);
    if(session==null&&!_accessRequired)return const SizedBox.shrink();
    final now=DateTime.now().toUtc();
    String fmt(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';}
    final expired=session==null||session.expired(now);
    final text=session==null?S.t('access.required')
      :expired?S.t('access.sessionExpired',{'email':session.email??''})
      :S.t('access.session',{'email':session.email??'',
          'date':session.expiresAt==null?'-':fmt(session.expiresAt!)});
    final color=session==null||expired||session.renewSoon(now)?Colors.deepOrange:null;
    return Padding(padding:const EdgeInsets.only(top:8),child:Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:8,children:[
      Icon(expired?Icons.lock_outline:Icons.lock_open,size:18,color:color),
      Text(text,style:TextStyle(color:color)),
      TextButton(onPressed:_signIn,child:Text(S.t(session==null?'access.signIn':'access.signInAgain'))),
      if(session!=null)TextButton(onPressed:() async {await AccessManager.instance.signOut(server);if(mounted)setState((){});},child:Text(S.t('access.signOut'))),
    ]));
  }

  static String _date(Object? v){
    final t=DateTime.tryParse('${v??''}')?.toLocal();
    if(t==null)return '';
    String two(int x)=>x.toString().padLeft(2,'0');
    return '${two(t.day)}/${two(t.month)}';
  }

  String _eventLabel(Map<String,dynamic> e){
    final state=S.t('eventState.${e['status']}');
    return [e['name'],state,_date(e['created_at'])].where((x)=>'${x??''}'.isNotEmpty).join(' · ');
  }

  Widget _eventPicker(){
    final current=_event.text.trim();
    final ids=_events.map((e)=>'${e['id']}').toSet();
    final items=[
      for(final e in _events)DropdownMenuItem(value:'${e['id']}',child:Text(_eventLabel(e),overflow:TextOverflow.ellipsis)),
      if(current.isNotEmpty&&!ids.contains(current))DropdownMenuItem(value:current,child:Text(S.t('settings.eventUnlisted',{'id':current}),overflow:TextOverflow.ellipsis)),
    ];
    final help=_eventsError!=null?S.t('settings.eventsError',{'error':_eventsError})
      :_eventsOffline?S.t('settings.eventsOffline')
      :(_events.isEmpty&&!_loadingEvents)?S.t('settings.eventsEmpty'):null;
    return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(child:DropdownButtonFormField<String>(
        key:ValueKey('$current|${_events.length}'),
        initialValue:current.isEmpty?null:current,
        isExpanded:true,
        decoration:InputDecoration(labelText:S.t('settings.event'),helperText:help,border:const OutlineInputBorder()),
        items:items,
        onChanged:(v)=>setState(()=>_event.text=v??''),
        validator:(_)=>_required(_event.text),
      )),
      const SizedBox(width:8),
      Padding(padding:const EdgeInsets.only(top:4),child:_loadingEvents
        ? const SizedBox(width:48,height:48,child:Padding(padding:EdgeInsets.all(12),child:CircularProgressIndicator(strokeWidth:2)))
        : IconButton(tooltip:S.t('settings.eventsRefresh'),onPressed:_loadEvents,icon:Icon(_eventsOffline?Icons.cloud_off:Icons.refresh))),
    ]);
  }

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
    final server=_serverText, event=_event.text.trim();
    final from=widget.initial;
    final changes=normalServer(server)!=normalServer(from.serverUrl)||event!=from.eventId;
    final waiting=(!widget.firstRun&&changes)?(widget.waitingFor?.call(from.serverUrl,from.eventId)??0):0;
    if(waiting>0){
      // Decision 5: Envoyer d'abord · Garder pour plus tard · Annuler.
      final choice=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
        title:Text(S.t('change.title')),
        content:Text(S.t('change.body',{'n':waiting,'event':from.eventId,'server':from.serverUrl})),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
          TextButton(onPressed:()=>Navigator.pop(c,'keep'),child:Text(S.t('change.keep'))),
          FilledButton(onPressed:()=>Navigator.pop(c,'send'),child:Text(S.t('change.sendFirst'))),
        ]));
      if(choice==null||!mounted)return;
      setState(()=>_saving=true);
      final left=choice=='send'&&widget.sendFirst!=null?await widget.sendFirst!(from.serverUrl,from.eventId):waiting;
      if(left>0&&mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('change.kept',{'n':left}))));
    }
    if(!mounted)return;
    setState(()=>_saving=true);
    await widget.onSave(widget.initial.copyWith(serverUrl:server,eventId:event,deviceId:_device.text.trim(),
      language:_language,callsign:_callsign.text.trim().toUpperCase(),aprsTxConsent:_aprsConsent));
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
        Focus(
          // Leaving the server field reloads the events of that server.
          onFocusChange:(f){if(!f)_loadEvents();},
          child:TextFormField(
            controller:_server,
            decoration:InputDecoration(labelText:S.t('settings.server'),hintText:defaultServerUrl,helperText:S.t('settings.serverHelp'),border:const OutlineInputBorder()),
            keyboardType:TextInputType.url,autocorrect:false,validator:_url,
            onFieldSubmitted:(_)=>_loadEvents(),
          ),
        ),
        _accessRow(),
        const SizedBox(height:16),
        if(widget.loadEvents!=null)...[
          _eventPicker(),
          // Manual identifier kept as a fallback (decision b).
          ExpansionTile(
            tilePadding:EdgeInsets.zero,
            initiallyExpanded:_eventsError!=null,
            title:Text(S.t('settings.eventAdvanced'),style:Theme.of(context).textTheme.bodyMedium),
            children:[TextFormField(
              controller:_event,
              decoration:InputDecoration(labelText:S.t('settings.eventId'),helperText:S.t('settings.eventIdHelp'),border:const OutlineInputBorder()),
              autocorrect:false,onChanged:(_)=>setState((){}),
            ),const SizedBox(height:8)],
          ),
        ]else TextFormField(
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
        const SizedBox(height:24),
        FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.check),label:Text(S.t('common.save'))),
        const SizedBox(height:16),
        SelectableText('SARCADE $appVersion${appBuild.isEmpty?'':' · $appBuild'}',textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodySmall),
      ])),
    ))),
  );
}
