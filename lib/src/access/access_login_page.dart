import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../l10n/strings.dart';
import 'access_manager.dart';
import 'access_session.dart';

/// Page of the server that hands the Access session over to the application.
Uri handoffUri(String server){
  var s=server.trim();
  while(s.endsWith('/')){s=s.substring(0,s.length-1);}
  return Uri.parse('$s/api/v0.1/access/handoff');
}

/// The embedded browser window is available on phones and tablets.
bool get embeddedSignIn=>!kIsWeb&&(defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS);

/// Opens the sign-in and returns true once the session is stored.
Future<bool> signInToServer(BuildContext context,String server) async {
  final ok=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>AccessLoginPage(server:server)));
  return ok==true;
}

/// « Se connecter » (« Accès protégé par Cloudflare Access »): the Cloudflare
/// page (email, then the code received by email) in an embedded browser
/// window on phones; on a computer the system browser, then the token is
/// pasted back.
class AccessLoginPage extends StatefulWidget {
  final String server;
  const AccessLoginPage({super.key,required this.server});
  @override State<AccessLoginPage> createState()=>_AccessLoginPageState();
}

class _AccessLoginPageState extends State<AccessLoginPage> {
  WebViewController? _web;
  int _progress=0;
  String? _error;
  final _pasted=TextEditingController();
  bool _done=false;

  @override void initState(){
    super.initState();
    if(embeddedSignIn){
      _web=WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel('SarcadeAccess',onMessageReceived:(m)=>_accept(m.message))
        ..setNavigationDelegate(NavigationDelegate(
          onProgress:(p){if(mounted)setState(()=>_progress=p);},
          onWebResourceError:(e){if(mounted&&e.isForMainFrame==true)setState(()=>_error=e.description);},
        ))
        ..loadRequest(handoffUri(widget.server));
    }
  }

  @override void dispose(){_pasted.dispose();super.dispose();}

  Future<void> _accept(String token) async {
    if(_done)return;
    final ok=await AccessManager.instance.save(widget.server,token);
    if(!mounted)return;
    if(ok){
      _done=true;
      final s=AccessManager.instance.sessionFor(widget.server);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t('access.connected',{'email':s?.email??''}))));
      Navigator.of(context).pop(true);
    }else{
      setState(()=>_error=S.t('access.invalidToken'));
    }
  }

  Future<void> _openBrowser() async {
    final ok=await launchUrl(handoffUri(widget.server),mode:LaunchMode.externalApplication);
    if(!ok&&mounted)setState(()=>_error=S.t('access.browserFailed'));
  }

  Future<void> _paste() async {
    final data=await Clipboard.getData(Clipboard.kTextPlain);
    if(data?.text!=null)_pasted.text=data!.text!.trim();
    if(mounted)setState((){});
  }

  @override
  Widget build(BuildContext context){
    final title=Text(S.t('access.title'));
    if(_web!=null){
      return Scaffold(
        appBar:AppBar(title:title,bottom:_progress<100?PreferredSize(preferredSize:const Size.fromHeight(3),child:LinearProgressIndicator(value:_progress/100)):null),
        body:Column(children:[
          if(_error!=null)MaterialBanner(content:Text(_error!),actions:[TextButton(onPressed:(){setState(()=>_error=null);_web!.loadRequest(handoffUri(widget.server));},child:Text(S.t('common.retry')))]),
          Expanded(child:WebViewWidget(controller:_web!)),
        ]),
      );
    }
    final session=AccessSession.fromToken(_pasted.text);
    return Scaffold(
      appBar:AppBar(title:title),
      body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(S.t('access.desktopIntro',{'server':widget.server}),style:Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height:16),
        FilledButton.icon(onPressed:_openBrowser,icon:const Icon(Icons.open_in_browser),label:Text(S.t('access.openBrowser'))),
        const SizedBox(height:24),
        Text(S.t('access.pasteIntro')),
        const SizedBox(height:8),
        TextField(controller:_pasted,maxLines:3,onChanged:(_)=>setState((){}),
          decoration:InputDecoration(border:const OutlineInputBorder(),labelText:S.t('access.token'),
            suffixIcon:IconButton(tooltip:S.t('access.paste'),onPressed:_paste,icon:const Icon(Icons.content_paste)))),
        if(session?.email!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(S.t('access.tokenFor',{'email':session!.email}))),
        if(_error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        const SizedBox(height:16),
        FilledButton(onPressed:session==null?null:()=>_accept(_pasted.text),child:Text(S.t('access.validate'))),
      ])))),
    );
  }
}
