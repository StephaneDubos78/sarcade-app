import 'package:flutter/material.dart';
import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';
import 'tv_code.dart';
import 'tv_qr_scan_page.dart';
import 'tv_view.dart';

/// « Afficher sur une TV » (any operator, decision of the porteur of
/// 29 October 2026): pair the screen opened on tv.sarcade.org by scanning
/// its QR code (Android, iPhone) or typing its code, then list and revoke
/// the screens of the event.
class TvScreensPage extends StatefulWidget {
  final SarcadeApi api; final String eventId;
  /// « Scanner le QR code » of Paramètres › Affichage: the camera opens at once.
  final bool scanOnOpen;
  const TvScreensPage({super.key,required this.api,required this.eventId,this.scanOnOpen=false});
  @override State<TvScreensPage> createState()=>_TvScreensPageState();
}

class _TvScreensPageState extends State<TvScreensPage> {
  List<Map<String,dynamic>>? _list; bool _busy=false; bool _offline=false;

  @override void initState(){
    super.initState();_load();
    if(widget.scanOnOpen&&canScanTvQr)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_scan();});
  }

  Future<void> _load() async {
    try{
      final l=await widget.api.displays(widget.eventId);
      if(mounted)setState((){_list=l;_offline=false;});
    }catch(_){
      if(mounted)setState(()=>_offline=true);
    }
  }

  void _say(String key){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(key))));
  }

  Future<void> _approve(String code) async {
    setState(()=>_busy=true);
    try{
      await widget.api.approveDisplay(code,widget.eventId);
      _say('tv.done');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'tv.unknownCode');
    }catch(_){
      _say('event.offline');
    }finally{
      if(mounted)setState(()=>_busy=false);
    }
  }

  Future<void> _scan() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const TvQrScanPage()));
    if(code!=null&&mounted)await _approve(code);
  }

  Future<void> _type() async {
    final ctrl=TextEditingController();
    final raw=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:Text(S.t('tv.type')),
      content:TextField(controller:ctrl,autofocus:true,textCapitalization:TextCapitalization.characters,
        decoration:InputDecoration(labelText:S.t('tv.code'),helperText:S.t('tv.codeHelp'))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(c,ctrl.text),child:Text(S.t('tv.show')))]));
    ctrl.dispose();
    if(raw==null||!mounted)return;
    final code=tvCodeFrom(raw);
    if(code==null){_say('tv.unknownCode');return;}
    await _approve(code);
  }

  Future<void> _revoke(Map<String,dynamic> d) async {
    try{
      await widget.api.revokeDisplay(widget.eventId,'${d['id']}');
      await _load();
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  /// Messages panel shown on the TV with « Envoyer ma vue ».
  bool _messages=true;
  TvOptions? _options(){final o=currentMapOptions?.call();return o==null?null:(layers:o.layers,opacity:o.opacity,messages:_messages);}

  /// « Envoyer ma vue » (view of the map of this device) or back to the
  /// automatic framing (null).
  Future<void> _view(Map<String,dynamic> d,{required bool mine}) async {
    final v=mine?currentMapView?.call():null;
    if(mine&&v==null){_say('tv.noMap');return;}
    try{
      await widget.api.sendDisplayView(widget.eventId,'${d['id']}',v==null?null:tvViewJson(v,options:_options()));
      _say(mine?'tv.viewSent':'tv.autoSent');
    }on SarcadeHttpException catch(e){
      _say(e.statusCode==401||e.statusCode==403?'tv.signIn':'event.offline');
    }catch(_){
      _say('event.offline');
    }
  }

  String _when(Object? s)=>s is num?DateTime.fromMillisecondsSinceEpoch((s*1000).toInt()).toLocal().toString().substring(0,16):'';

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context); final list=_list;
    return Scaffold(appBar:AppBar(title:Text(S.t('tv.menu'))),
      body:AbsorbPointer(absorbing:_busy,child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(S.t('tv.help'),style:t.textTheme.bodyLarge),
        const SizedBox(height:16),
        if(canScanTvQr)...[
          FilledButton.icon(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:Text(S.t('tv.scan')),
            style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52))),
          const SizedBox(height:8),
        ],
        OutlinedButton.icon(onPressed:_type,icon:const Icon(Icons.keyboard_outlined),label:Text(S.t('tv.type')),
          style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(52))),
        if(_busy)const Padding(padding:EdgeInsets.only(top:16),child:LinearProgressIndicator()),
        const SizedBox(height:24),
        Text(S.t('tv.list'),style:t.textTheme.titleMedium),
        SwitchListTile(contentPadding:EdgeInsets.zero,value:_messages,onChanged:(v)=>setState(()=>_messages=v),
          title:Text(S.t('tv.messagesPanel')),subtitle:Text(S.t('tv.messagesPanelHelp'))),
        if(_offline)ListTile(leading:const Icon(Icons.cloud_off),title:Text(S.t('event.offline')),
          trailing:TextButton(onPressed:_load,child:Text(S.t('common.retry'))))
        else if(list==null)const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()))
        else if(list.isEmpty)ListTile(title:Text(S.t('tv.none')))
        else for(final d in list)ListTile(
          leading:Icon(d['active']==true?Icons.tv:Icons.tv_off,color:d['active']==true?Colors.green:null),
          title:Text('${S.t('tv.code')} ${d['code']??''}'),subtitle:Text(S.t('tv.until',{'t':_when(d['expires'])})),
          trailing:d['active']==true?PopupMenuButton<String>(
            onSelected:(a){if(a=='view')_view(d,mine:true);if(a=='auto')_view(d,mine:false);if(a=='revoke')_revoke(d);},
            itemBuilder:(_)=>[
              PopupMenuItem(value:'view',child:ListTile(leading:const Icon(Icons.cast),title:Text(S.t('tv.sendView')),subtitle:Text(S.t('tv.sendViewHelp2')))),
              PopupMenuItem(value:'auto',child:ListTile(leading:const Icon(Icons.fit_screen),title:Text(S.t('tv.auto')))),
              PopupMenuItem(value:'revoke',child:ListTile(leading:const Icon(Icons.tv_off),title:Text(S.t('tv.revoke')))),
            ]):null),
      ])));
  }
}
