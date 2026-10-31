import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../ui/overlay_page.dart';
import '../../ui/choice_pills.dart';
import 'package:flutter/services.dart';
import '../../access/access_login_page.dart';
import '../../access/access_manager.dart';
import '../../access/access_session.dart';
import '../../config/app_config.dart';
import '../../config/saved_servers.dart';
import '../../config/version.dart';
import 'about_page.dart';
import 'notifications_panel.dart';
import '../../ui/theme.dart' show themeMode;
import '../map/drawing/drawing_controller.dart' show defaultDrawColor;
import '../../ui/color_palette.dart';
import '../../l10n/strings.dart';
import '../../offline/outbox_policy.dart' show normalServer;
import '../../operations/event_settings.dart';
import '../../services/notification_service.dart';
import '../../models/comm_group.dart' show isPco, myRoles;
import '../../services/sarcade_api.dart' show SarcadeApi, SarcadeHttpException;
import 'diagnostics_panel.dart';
import 'event_settings_section.dart';
import '../bearings/signal_defaults_page.dart';
import '../../offline/local_store.dart';
import '../compass/shared_compass.dart';
import '../../services/power_state.dart';
import '../../ui/save_bar.dart';
import '../../ui/action_buttons.dart';
import '../../services/event_names.dart';
import '../../ui/link_status.dart';
import '../measure/external_maps.dart' show openInChoices, navAppMineKey;

/// Operator settings: server address, event and terminal identifier,
/// language, radio callsign. Lets one APK serve every field operator
/// instead of one build per terminal.
class SettingsPage extends StatefulWidget {
  final AppConfig initial;
  final Future<void> Function(AppConfig) onSave;
  final bool firstRun;
  /// Opens the logbook of the active session, not the unsaved form values.
  final VoidCallback? onOpenLogbook;
  /// Events of a server (« Choix de l'événement dans une liste »): fetched
  /// list, and the last list known for offline use.
  final Future<List<Map<String,dynamic>>> Function(String server)? loadEvents;
  final List<Map<String,dynamic>> Function(String server)? cachedEvents;
  /// Items still waiting for a server and event, and « Envoyer d'abord »
  /// returning what is left (« Robustesse de la synchronisation »).
  final int Function(String server,String eventId)? waitingFor;
  final Future<int> Function(String server,String eventId)? sendFirst;
  /// Remembered servers (« Mémorisation des serveurs »), read again after
  /// each successful connection, and saved after a rename or a removal.
  final List<SavedServer> Function()? readServers;
  final Future<void> Function(List<SavedServer>)? saveServers;
  /// Day / night / automatic chosen: applied at once, kept by the caller.
  final void Function(ThemeMode)? onThemeChanged;
  /// Active session, for Paramètres › Événement (PCO only).
  final SarcadeApi? api;
  /// Device store: caches what the administrator saves (default frequencies).
  final LocalStore? store;
  const SettingsPage({super.key,required this.initial,required this.onSave,this.firstRun=false,
    this.loadEvents,this.cachedEvents,this.waitingFor,this.sendFirst,this.readServers,this.saveServers,this.onOpenLogbook,this.onThemeChanged,this.api,this.store});
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
  late int _drawColor=defaultDrawColor(widget.initial.drawColor);
  bool _saving=false;
  /// Something changed since the screen opened (or since the last save):
  /// « Enregistrer » is greyed until then. Always on at the first setup.
  bool _dirty=false;
  void _touch(){if(!_dirty)setState(()=>_dirty=true);}
  List<Map<String,dynamic>> _events=[];
  bool _loadingEvents=false, _eventsOffline=false, _accessRequired=false;
  String? _eventsError;
  late List<SavedServer> _servers=widget.readServers?.call()??const [];

  @override void initState(){
    super.initState();
    // Red dot on Paramètres: the screen opens on the Diagnostic (card
    // « Diagnostic, point d'arrivée unique des problèmes », 30 Oct 2026).
    if(!widget.firstRun&&diagnosticsAlert())_tab=_tabs.indexOf('diagnostics');
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
      setState((){_events=list;_eventsOffline=false;_accessRequired=false;_servers=widget.readServers?.call()??_servers;});
    }on AccessRequiredException{
      // Protected by Cloudflare Access: sign in first, then the list comes.
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_accessRequired=true;});
    }on SarcadeHttpException catch(e){
      // The list could not be read: the last known one is shown.
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_eventsError='HTTP ${e.statusCode}';});
    }catch(_){
      if(mounted)setState((){_events=widget.cachedEvents?.call(server)??[];_eventsOffline=true;});
    }finally{
      if(mounted)setState(()=>_loadingEvents=false);
    }
  }

  /// A remembered server chosen: its address, last event and terminal.
  void _chooseServer(SavedServer server){
    setState((){
      _server.text=server.url;
      if(server.lastEvent!=null)_event.text=server.lastEvent!;
      if(server.lastDevice!=null&&server.lastDevice!.isNotEmpty)_device.text=server.lastDevice!;
      _events=widget.cachedEvents?.call(server.url)??[];
    });
    _loadEvents();
  }

  Future<void> _renameServer(SavedServer server) async {
    final ctrl=TextEditingController(text:server.label);
    final label=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('servers.rename')),
      content:TextField(controller:ctrl,autofocus:true,decoration:InputDecoration(labelText:S.t('servers.label'),helperText:server.url)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text.trim()),child:Text(S.t('common.save'))),
      ]));
    ctrl.dispose();
    if(label==null||!mounted)return;
    final list=[for(final s in _servers)serverKey(s.url)==serverKey(server.url)?s.copyWith(label:label.isEmpty?defaultLabel(s.url):label):s];
    setState(()=>_servers=list);
    await widget.saveServers?.call(list);
  }

  Future<void> _removeServer(SavedServer server) async {
    final waiting=server.lastEvent==null?0:(widget.waitingFor?.call(server.url,server.lastEvent!)??0);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('servers.remove')),
      content:Text([S.t('servers.removeBody',{'label':server.label,'url':server.url}),
        if(waiting>0)S.t('servers.removeWaiting',{'n':waiting})].join('\n\n')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('servers.removeConfirm'))),
      ]));
    if(ok!=true||!mounted)return;
    final list=_servers.where((s)=>serverKey(s.url)!=serverKey(server.url)).toList();
    setState(()=>_servers=list);
    await widget.saveServers?.call(list);
    // The Cloudflare Access session of that server goes with it.
    await AccessManager.instance.signOut(server.url);
  }

  /// Remembered servers (« Paramètres › Général au même style que
  /// l'onglet Événement »): the list, a pencil to rename, the bin to forget;
  /// a new address is typed in a small window (« + Ajouter un serveur »).
  /// Rebuilds the list after « + Ajouter un serveur… » (back to the current one).
  int _pickRev=0;
  bool get _serverList=>!widget.firstRun&&widget.readServers!=null&&_servers.isNotEmpty;

  Widget _serverPicker(){
    final current=findServer(_servers,_serverText);
    return _withActions(DropdownButtonFormField<String>(
          key:ValueKey('servers|${current?.url}|${_servers.length}|$_serverText|$_pickRev'),
          initialValue:current?.url??_serverText,
          isExpanded:true,
          // The row already says « Serveur » (29 Oct 2026: no word twice).
          decoration:_field(),
          items:[
            // The address only when it differs from the name (revue n° 62).
            for(final s in _servers)DropdownMenuItem(value:s.url,child:Text(s.label==s.shortAddress?s.label:'${s.label} · ${s.shortAddress}',overflow:TextOverflow.ellipsis)),
            if(current==null&&_serverText.isNotEmpty)DropdownMenuItem(value:_serverText,child:Text(S.t('servers.new',{'url':_serverText}),overflow:TextOverflow.ellipsis)),
            // « + Ajouter un serveur… » at the bottom of the list (16 h 38).
            DropdownMenuItem(key:const ValueKey('server-add'),value:addServerValue,child:Text(S.t('servers.addItem'),overflow:TextOverflow.ellipsis)),
          ],
          onChanged:(v){
            if(v==addServerValue){unawaited(_addServer());setState(()=>_pickRev++);return;}
            final s=v==null?null:findServer(_servers,v);if(s!=null){_chooseServer(s);_touch();}},
          validator:(_)=>_url(_server.text),
        ),[
        if(current!=null)...[
          RoundIconButton(tooltip:S.t('servers.rename'),onPressed:()=>_renameServer(current),icon:Icons.edit_outlined),
          if(canRemoveServer(current))RoundIconButton(tooltip:S.t('servers.remove'),onPressed:()=>_removeServer(current),icon:Icons.delete_outline),
        ],
      ]);
  }

  Future<void> _addServer() async {
    final ctrl=TextEditingController(text:'https://');
    final url=await showDialog<String>(context:context,builder:(c)=>AlertDialog(
      title:Text(S.t('servers.add')),
      content:TextField(controller:ctrl,autofocus:true,keyboardType:TextInputType.url,autocorrect:false,
        decoration:InputDecoration(labelText:S.t('settings.server'),hintText:defaultServerUrl,helperText:S.t('settings.serverHelp'),helperMaxLines:3)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text.trim()),child:Text(S.t('common.ok'))),
      ]));
    ctrl.dispose();
    if(url==null||!mounted)return;
    if(_url(url)!=null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('settings.urlExpected'))));return;}
    setState((){_server.text=url;_events=widget.cachedEvents?.call(_serverText)??[];_dirty=true;});
    _loadEvents();
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
      OutlinedButton(onPressed:_signIn,child:Text(S.t(session==null?'access.signIn':'access.signInAgain'))),
      if(session!=null)OutlinedButton(onPressed:() async {await AccessManager.instance.signOut(server);if(mounted)setState((){});},child:Text(S.t('access.signOut'))),
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
    return _withActions(DropdownButtonFormField<String>(
        key:ValueKey('$current|${_events.length}'),
        initialValue:current.isEmpty?null:current,
        isExpanded:true,
        decoration:_field(label:widget.firstRun?S.t('settings.event'):null,help:help),
        items:items,
        onChanged:(v)=>setState((){_event.text=v??'';_dirty=true;}),
        validator:(_)=>_required(_event.text),
      ),[
      _loadingEvents
        ? const SizedBox(width:48,height:48,child:Padding(padding:EdgeInsets.all(12),child:CircularProgressIndicator(strokeWidth:2)))
        : IconButton(tooltip:S.t('settings.eventsRefresh'),onPressed:_loadEvents,icon:Icon(_eventsOffline?Icons.cloud_off:Icons.refresh)),
      if(_canCreateEvent)IconButton(key:const ValueKey('event-new'),tooltip:S.t('events.new'),onPressed:_createEvent,icon:const Icon(Icons.add)),
    ]);
  }

  /// The PCO creates an event from the app, on the server it is linked to.
  bool get _canCreateEvent=>widget.api!=null&&!widget.firstRun&&isPco(widget.initial.deviceId)
    &&normalServer(_serverText)==normalServer(widget.initial.serverUrl);

  Future<void> _createEvent() async {
    final name=TextEditingController(); var kind='exercise';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:Text(S.t('events.new')),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(key:const ValueKey('event-new-name'),controller:name,autofocus:true,decoration:InputDecoration(labelText:S.t('events.name'))),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(key:const ValueKey('event-new-kind'),initialValue:kind,isExpanded:true,decoration:InputDecoration(labelText:S.t('events.model')),
          items:[for(final k in eventKinds)DropdownMenuItem(value:k,child:Text(S.t('events.kind.$k')))],onChanged:(v)=>set(()=>kind=v??kind)),
        const SizedBox(height:6),
        Text(S.t('events.modulesOf',{'m':eventKindModules(kind)}),style:Theme.of(c).textTheme.bodySmall),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('common.cancel'))),
        FilledButton(key:const ValueKey('event-new-create'),onPressed:()=>Navigator.pop(c,true),child:Text(S.t('events.create')))])));
    final n=name.text.trim(); name.dispose();
    if(ok!=true||n.isEmpty||!mounted)return;
    final m=ScaffoldMessenger.of(context);
    try{
      final e=await widget.api!.createEvent(n,kind);
      if(!mounted)return;
      await _loadEvents();
      if(!mounted)return;
      setState((){_event.text='${e['id']}';_dirty=true;});
      m.showSnackBar(SnackBar(content:Text(S.t('events.created',{'n':n}))));
    }on SarcadeHttpException catch(e){
      m.showSnackBar(SnackBar(content:Text(S.t(e.statusCode==403?'events.pcoOnly':'events.createFailed',{'e':'HTTP ${e.statusCode}'}))));
    }catch(_){
      m.showSnackBar(SnackBar(content:Text(S.t('events.createFailed',{'e':S.t('settings.eventsOffline')}))));
    }
  }

  /// « ADRASEC », « Course » or « aucun (Core seul) », for the dialog.
  String eventKindModules(String kind){
    final m=modulesOfKind(kind);
    return m.isEmpty?S.t('modules.none'):m.map((id)=>S.t('modules.$id')).join(', ');
  }

  /// ADRASEC on for the event this device follows (Core and modules).
  bool get _adrasec=>eventModules(widget.store?.eventSettings(widget.initial.eventId)).contains('adrasec');

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
      language:_language,callsign:_callsign.text.trim().toUpperCase(),aprsTxConsent:_aprsConsent,
      immediateBypassDnd:_bypassDnd,drawColor:_drawColor));
    if(mounted)setState((){_saving=false;_dirty=false;});
  }

  /// Tabs of the screen (« Charte graphique épurée »); the first setup only
  /// shows what is needed to start.
  List<String> get _tabs=>widget.firstRun
    ?['general','profile','display','about']
    :['general',if(_eventTab)'event','profile','display','notifications','diagnostics','about'];
  bool get _eventTab=>widget.api!=null&&isPco(widget.initial.deviceId);
  int _tab=0;

  /// One setting per line: bold label and grey help on the left (under it
  /// on a phone), the control on the right.
  Widget _row(String label,{String? help,String? tip,required Widget child}){
    final t=Theme.of(context);
    final head=Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Flexible(child:Text(label,style:t.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w600))),
        // Fewer words (card « Paramètres › Général, mise en page », 16 h 38):
        // the explanation in an ⓘ rather than grey text.
        if(tip!=null)Tooltip(message:tip,triggerMode:TooltipTriggerMode.tap,child:Padding(padding:const EdgeInsets.only(left:6),
          child:Icon(Icons.info_outline,size:16,color:t.colorScheme.onSurfaceVariant))),
      ]),
      if(help!=null)Padding(padding:const EdgeInsets.only(top:2),child:Text(help,style:t.textTheme.bodySmall?.copyWith(color:t.colorScheme.onSurfaceVariant))),
    ]);
    return Column(children:[
      // Width of the screen, not a LayoutBuilder: a field keeps its focus
      // while the keyboard opens.
      Padding(padding:const EdgeInsets.symmetric(vertical:14),child:MediaQuery.sizeOf(context).width>=640
        ? Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(flex:2,child:head),const SizedBox(width:24),Expanded(flex:3,child:child)])
        : Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[head,const SizedBox(height:8),child])),
      const Divider(height:1),
    ]);
  }

  /// Compact field; its label stays inside (read by screen readers and the
  /// end-to-end tests).
  InputDecoration _field({String? label,String? hint,String? help})=>InputDecoration(isDense:true,labelText:label,hintText:hint,helperText:help,helperMaxLines:3,
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(8)));


  /// Read-only value with an optional text action on the right (« Ouvrir »).
  Widget _value(String text,{String? action,VoidCallback? onAction})=>Row(children:[
    Expanded(child:SelectableText(text)),
    if(action!=null)OutlinedButton(onPressed:onAction,child:Text(action)),
  ]);

  /// Compact field on the right of a row (label inside, read by screen
  /// readers and the end-to-end tests).
  Widget _compact(Widget field)=>Align(alignment:Alignment.centerLeft,child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:field));

  /// First setup: the plain form of before (fields one under the other),
  /// kept as it is for the end-to-end tests of the first run.
  Widget _firstRunTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Padding(padding:const EdgeInsets.only(top:12),child:Text(S.t('settings.intro'))),
    Padding(padding:const EdgeInsets.only(top:14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Focus(
        // Leaving the server field reloads the events of that server.
        onFocusChange:(f){if(!f)_loadEvents();},
        child:TextFormField(
          controller:_server,
          decoration:_field(label:S.t('settings.server'),hint:defaultServerUrl,help:S.t('settings.serverHelp')),
          keyboardType:TextInputType.url,autocorrect:false,validator:_url,
          onFieldSubmitted:(_)=>_loadEvents(),
          onChanged:(_)=>setState((){}),
        ),
      ),
      _accessRow(),
    ])),
    Padding(padding:const EdgeInsets.only(top:14),child:widget.loadEvents!=null?_eventPicker():TextFormField(
      controller:_event,decoration:_field(label:S.t('settings.event')),autocorrect:false,validator:_required)),
    Padding(padding:const EdgeInsets.only(top:14),child:TextFormField(
      controller:_device,decoration:_field(label:S.t('settings.device'),hint:'TERRAIN-01',help:S.t('settings.deviceHelp')),autocorrect:false,validator:_required)),
    const SizedBox(height:8),
  ]);

  Widget _generalTab()=>widget.firstRun?_firstRunTab():Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    _row(S.t('settings.serverRow'),tip:S.t('settings.serverHelp'),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(_serverList)_serverPicker()
      else _withActions(Focus(
        // Leaving the server field reloads the events of that server.
        onFocusChange:(f){if(!f)_loadEvents();},
        child:TextFormField(
          controller:_server,
          decoration:_field(hint:defaultServerUrl),
          keyboardType:TextInputType.url,autocorrect:false,validator:_url,
          onFieldSubmitted:(_)=>_loadEvents(),
          onChanged:(_)=>setState((){}),
        ),
      )),
      _accessRow(),
    ])),
    _row(S.t('settings.eventRow'),tip:S.t('settings.eventHelp'),child:widget.loadEvents!=null?_eventPicker():_withActions(TextFormField(
      controller:_event,decoration:_field(),autocorrect:false,validator:_required))),
    _row(S.t('settings.deviceRow'),tip:S.t('settings.deviceHelp'),child:_withActions(TextFormField(
      controller:_device,decoration:_field(hint:'TERRAIN-01'),autocorrect:false,validator:_required))),
  ]);

  /// Serveur, Événement suivi and Terminal of the same width, their buttons
  /// (pencil, bin, refresh) in one column on the right (16 h 38).
  static const double _actionsWidth=96;
  Widget _withActions(Widget field,[List<Widget> actions=const []])=>Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(child:field),
    SizedBox(width:_actionsWidth,child:Row(mainAxisAlignment:MainAxisAlignment.end,children:actions)),
  ]);

  Widget _profileTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    _row(S.t('settings.callsignRow'),help:S.t('settings.callsignHelp'),child:_compact(TextFormField(
      controller:_callsign,decoration:_field(hint:'F4ABC-7'),
      autocorrect:false,textCapitalization:TextCapitalization.characters,validator:_callsignCheck))),
    // Colour of every new drawing (existing objects keep theirs).
    _row(S.t('settings.drawColor'),help:S.t('settings.drawColorHelp'),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      // Same 4 × 4 palette as the drawings and the groups (30 Oct 2026, 13 h 25);
      // « Autre couleur » under the grid, on the left (revue n° 66).
      ColorGrid(colors:paletteWith(_drawColor),selected:_drawColor,onPick:(c)=>setState((){_drawColor=c;_dirty=true;})),
      const SizedBox(height:8),
      ActionChip(avatar:const Icon(Icons.palette_outlined,size:18),label:Text(S.t('settings.otherColor')),onPressed:_pickOtherColor),
    ])),
    // « Toujours ouvrir avec … » of « Ouvrir dans… », changed here
    // (31 Oct 2026); applied at once on this device.
    if(widget.store!=null)_row(S.t('settings.navApp'),child:Align(alignment:Alignment.centerRight,child:DropdownButton<String>(
      key:const ValueKey('settings-nav-app'),value:widget.store!.preference(navAppMineKey)??'',
      items:[DropdownMenuItem(value:'',child:Text(S.t('settings.navAppAsk'))),
        for(final a in openInChoices(android:!kIsWeb&&defaultTargetPlatform==TargetPlatform.android,ios:!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS))
          if(a!='other')DropdownMenuItem(value:a,child:Text(S.t('ext.app.$a')))],
      onChanged:(v) async {await widget.store!.setPreference(navAppMineKey,v==null||v.isEmpty?null:v);if(mounted)setState((){});}))),
    // Under « Couleur de dessin » (29 Oct 2026); ADRASEC module only.
    if(_adrasec)_row(S.t('settings.aprsConsent'),help:S.t('settings.aprsConsentHelp'),child:Align(alignment:Alignment.centerRight,
      child:Switch(value:_aprsConsent,onChanged:(v)=>setState((){_aprsConsent=v;_dirty=true;})))),
  ]);

  /// « Autre couleur »: free choice of the hue, light enough to read on
  /// the map.
  Future<void> _pickOtherColor() async {
    var hue=HSVColor.fromColor(Color(_drawColor)).hue;
    final picked=await showDialog<int>(context:context,builder:(c)=>StatefulBuilder(builder:(c,set){
      final color=HSVColor.fromAHSV(1,hue,0.8,0.85).toColor();
      return AlertDialog(title:Text(S.t('settings.otherColor')),content:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:56,height:56,decoration:BoxDecoration(color:color,shape:BoxShape.circle)),
        Slider(value:hue,min:0,max:359,onChanged:(v)=>set(()=>hue=v)),
      ]),actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,color.toARGB32()),child:Text(S.t('common.ok'))),
      ]);
    }));
    if(picked!=null&&mounted)setState((){_drawColor=picked;_dirty=true;});
  }

  Widget _displayTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    // Applied at once, kept on the device (not part of the saved form).
    _row(S.t('settings.theme'),help:S.t('settings.themeHelp'),child:ValueListenableBuilder<ThemeMode>(valueListenable:themeMode,
      builder:(context,mode,_)=>Align(alignment:Alignment.centerLeft,child:ChoicePills<ThemeMode>(
        choices:[
          (value:ThemeMode.light,icon:Icons.light_mode_outlined,label:S.t('settings.themeDay')),
          (value:ThemeMode.dark,icon:Icons.dark_mode_outlined,label:S.t('settings.themeNight')),
          (value:ThemeMode.system,icon:Icons.brightness_auto_outlined,label:S.t('settings.themeAuto')),
        ],
        selected:mode,
        onSelected:(v){themeMode.value=v;widget.onThemeChanged?.call(v);},
      )))),
    _row(S.t('settings.languageRow'),child:_compact(DropdownButtonFormField<String>(
      initialValue:_language,isExpanded:true,
      decoration:_field(),
      items:[
        DropdownMenuItem(value:'system',child:Text(S.t('settings.languageSystem'))),
        const DropdownMenuItem(value:'fr',child:Text('Français')),
        const DropdownMenuItem(value:'en',child:Text('English')),
      ],
      onChanged:(v)=>setState((){_language=v??'system';_dirty=true;}),
    ))),
    // Smart TV screens: managed in Outils › Afficher sur une TV only
    // (« Écrans Smart TV en double », 30 Oct 2026).
    // Battery card (30 Oct 2026, point E): applied at once, kept on the device.
    _row(S.t('power.saver'),help:S.t('power.saverHelp'),child:ListenableBuilder(listenable:PowerState.instance,
      builder:(context,_)=>Align(alignment:Alignment.centerRight,child:Switch(key:const ValueKey('power-saver'),
        value:PowerState.instance.saver,onChanged:(v){PowerState.instance.setSaver(v);})))),
  ]);

  Widget _notificationsTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    if(NotificationService.supportsDndBypass)_row(S.t('settings.dndBypass'),help:S.t('settings.dndBypassHelp'),child:Align(alignment:Alignment.centerRight,
      child:Switch(value:_bypassDnd,onChanged:(v) async {
        setState((){_bypassDnd=v;_dirty=true;});
        if(!v)return;
        final granted=await NotificationService().enableDndBypass();
        if(!granted&&mounted){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('settings.dndPending'))));
        }
      }))),
    NotificationsPanel(api:widget.api,eventId:widget.initial.eventId,deviceId:widget.initial.deviceId,store:widget.store,row:_row),
  ]);

  /// Active session only: what is shown does not depend on unsaved edits.
  Widget _diagnosticsTab()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Padding(padding:const EdgeInsets.only(top:12),child:Text(S.t('diagnostics.description'))),
    // Name of the event; its identifier in the copyable report only (revue n° 60).
    _row(S.t('diagnostics.event'),child:EventNameBuilder(api:widget.api,eventId:widget.initial.eventId,builder:(_,n)=>_value(n))),
    _row(S.t('diagnostics.server'),child:_value(widget.initial.serverUrl)),
    _row(S.t('diagnostics.device'),child:_value(widget.initial.deviceId)),
    EventNameBuilder(api:widget.api,eventId:widget.initial.eventId,builder:(_,n)=>_row(S.t('map.logbook'),help:S.t('diagnostics.activeEvent',{'event':n}),
      child:_value('',action:S.t('diagnostics.open'),onAction:widget.onOpenLogbook))),
    // « Copier » at the far right (29 Oct 2026).
    _row(S.t('diagnostics.version'),child:Builder(builder:(c){
      final v='SARCADE $appVersionFull${appBuild.isEmpty?'':' · $appBuild'}';
      return Row(children:[Expanded(child:SelectableText(v)),
        IconButton(tooltip:S.t('common.copy'),icon:const Icon(Icons.copy_outlined),onPressed:() async {
          await Clipboard.setData(ClipboardData(text:v));
          if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(S.t('common.copied'))));
        })]);
    })),
    if(VersionStatus.shown)const Padding(padding:EdgeInsets.only(bottom:12),child:VersionStatus()),
    // Battery card (30 Oct 2026, point F).
    _row(S.t('power.consumption'),child:Builder(builder:(_){final p=PowerState.instance;
      return Text(consumptionLine(trackingS:p.trackingS,moving:p.trackingMoving,reduced:p.gpsReduced,
        compass:SharedCompass.instance.running,saver:p.saver,t:S.t));})),
    // Cet appareil, Liaisons, Serveur (PCO / admin), « Copier le rapport » (lot 5).
    if(widget.api!=null)DiagnosticsPanel(api:widget.api!,server:widget.initial.serverUrl,eventId:widget.initial.eventId,actorId:widget.initial.deviceId),
  ]);

  Widget _tabBody(String id)=>switch(id){
    'general'=>_generalTab(),'profile'=>_profileTab(),'display'=>_displayTab(),
    'notifications'=>_notificationsTab(),'diagnostics'=>_diagnosticsTab(),
    'event'=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      EventSettingsSection(api:widget.api!,eventId:widget.initial.eventId,actorId:widget.initial.deviceId),
      // Default frequencies of the bearing tool: administrator only.
      if(myRoles.contains('admin')&&_adrasec)_row(S.t('signals.title'),help:S.t('signals.rowHelp'),child:Align(alignment:Alignment.centerRight,child:OutlinedButton(
        onPressed:()=>showOverlayPage<void>(context,(_)=>SignalDefaultsPage(api:widget.api!,store:widget.store)),
        child:Text(S.t('signals.manage'))))),
    ]),
    _=>const Padding(padding:EdgeInsets.only(top:16),child:SarcadeAboutContent()),
  };

  void _cancel(){
    final i=widget.initial;
    setState((){
      _server.text=i.serverUrl;_event.text=i.eventId;_device.text=i.deviceId;_callsign.text=i.callsign;
      _language=i.language;_aprsConsent=i.aprsTxConsent;_bypassDnd=i.immediateBypassDnd;_drawColor=defaultDrawColor(i.drawColor);
      _dirty=false;
    });
    _form.currentState?.reset();
    final nav=Navigator.of(context);
    if(nav.canPop())nav.pop();
  }

  Future<void> _trySave() async {
    // A refused field may sit in a hidden tab: show the first one.
    final general=_url(_server.text)!=null||_required(_event.text)!=null||_required(_device.text)!=null;
    if(general&&_tab!=0){
      setState(()=>_tab=0);
    }else if(!general&&_callsignCheck(_callsign.text)!=null){
      setState(()=>_tab=_tabs.indexOf('profile'));
    }
    await WidgetsBinding.instance.endOfFrame;
    if(mounted)await _save();
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context);
    return Scaffold(
      // Same surface as the content in both themes (revue n° 68).
      appBar:LinkedAppBar(linkStatus:!widget.firstRun,automaticallyImplyLeading:!widget.firstRun,backgroundColor:t.colorScheme.surface,surfaceTintColor:Colors.transparent,scrolledUnderElevation:0),
      // Fixed save bar at the bottom (charte « style Play Console »); none on
      // Diagnostic and À propos, nothing to save there (revue n° 64).
      bottomNavigationBar:settingsShowsSaveBar(tab:_tabs[_tab.clamp(0,_tabs.length-1)],firstRun:widget.firstRun,dirty:_dirty)?SaveBar(changed:widget.firstRun||_dirty,saving:_saving,onSave:_trySave,
        onCancel:widget.firstRun?null:_cancel):null,
      body:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:900),
        child:Form(key:_form,onChanged:widget.firstRun?null:_touch,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.fromLTRB(20,0,20,4),child:Text(widget.firstRun?S.t('settings.firstRun'):S.t('settings.title'),
            style:t.textTheme.headlineMedium)),
          // « En-tête allégé » (30 Oct 2026, 2 h 56): no lines under the
          // title; server, event and terminal stay in Diagnostic.
          if(widget.firstRun)Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Text(S.t('settings.subtitleFirst'),
            style:t.textTheme.bodyMedium?.copyWith(color:t.colorScheme.onSurfaceVariant))),
          const SizedBox(height:8),
          // Underlined tabs; every tab stays built so that the form keeps
          // and validates all its fields.
          DefaultTabController(key:ValueKey(_tabs.length),length:_tabs.length,initialIndex:_tab,child:Builder(builder:(context){
            final c=DefaultTabController.of(context);
            if(c.index!=_tab)c.animateTo(_tab);
            return TabBar(isScrollable:true,tabAlignment:TabAlignment.start,
              onTap:(i)=>setState(()=>_tab=i),
              tabs:[for(final id in _tabs)id=='diagnostics'&&diagnosticsAlert()
                ?Tab(child:Badge(key:const ValueKey('diag-tab-alert'),smallSize:8,offset:const Offset(8,-2),child:Text(S.t('settings.tab.$id'))))
                :Tab(text:S.t('settings.tab.$id'))]);
          })),
          const Divider(height:1),
          Expanded(child:IndexedStack(index:_tab,children:[for(final id in _tabs)ListView(
            padding:const EdgeInsets.fromLTRB(20,0,20,24),children:[_tabBody(id)])])),
        ])),
      ))),
    );
  }
}

/// The save bar, except on Diagnostic and À propos with nothing changed.
bool settingsShowsSaveBar({required String tab,required bool firstRun,required bool dirty})=>firstRun||dirty||!(tab=='diagnostics'||tab=='about');
/// Value of « + Ajouter un serveur… » in the list of servers.
const addServerValue='\u0000add-server';
