import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'access_session.dart';

/// Cloudflare Access sessions of the servers (« Accès protégé par Cloudflare
/// Access »): kept in the secure storage of the device (Keystore, Keychain,
/// Windows credentials), one per server, never shown nor logged.
///
/// In a browser nothing is needed: the browser holds the session cookie.
class AccessManager extends ChangeNotifier {
  AccessManager._();
  static final instance=AccessManager._();

  static const _prefix='sarcade.access.';
  final _storage=const FlutterSecureStorage();
  final _sessions=<String,AccessSession>{};
  /// Servers whose last answer was the Cloudflare sign-in.
  final _required=<String>{};

  /// Reads the stored sessions at start; a storage failure only means the
  /// operator signs in again.
  Future<void> load() async {
    if(kIsWeb)return;
    try{
      final all=await _storage.readAll();
      all.forEach((k,v){
        if(!k.startsWith(_prefix))return;
        final s=AccessSession.fromToken(v);
        if(s!=null)_sessions[k.substring(_prefix.length)]=s;
      });
    }catch(_){/* signed out */}
  }

  AccessSession? sessionFor(String server)=>_sessions[accessOrigin(server)];
  bool requiredFor(String server)=>_required.contains(accessOrigin(server));

  /// Headers for a call: the token only goes to the server it belongs to
  /// (a local address never receives it), and never once expired.
  Map<String,String> headersFor(Uri url){
    if(kIsWeb||!(url.scheme=='http'||url.scheme=='https'||url.scheme=='ws'||url.scheme=='wss'))return const {};
    final origin=accessOrigin(url.replace(scheme:url.scheme=='wss'?'https':url.scheme=='ws'?'http':url.scheme).toString());
    final s=_sessions[origin];
    if(s==null||s.expired(DateTime.now().toUtc()))return const {};
    return s.headers;
  }

  void markRequired(Uri url){
    if(_required.add(accessOrigin(url.toString())))notifyListeners();
  }

  void markOk(Uri url){
    if(_required.remove(accessOrigin(url.toString())))notifyListeners();
  }

  /// Stores the token handed over by the server page. False if it is not a
  /// valid, unexpired token.
  Future<bool> save(String server,String token) async {
    final s=AccessSession.fromToken(token);
    if(s==null||s.expired(DateTime.now().toUtc()))return false;
    final origin=accessOrigin(server);
    _sessions[origin]=s;
    _required.remove(origin);
    try{await _storage.write(key:'$_prefix$origin',value:s.token);}catch(_){/* kept for this run */}
    notifyListeners();
    return true;
  }

  Future<void> signOut(String server) async {
    final origin=accessOrigin(server);
    _sessions.remove(origin);
    try{await _storage.delete(key:'$_prefix$origin');}catch(_){}
    notifyListeners();
  }
}

/// HTTP client of the application: adds the Access session to the calls of
/// its server and recognises when the Cloudflare sign-in answered instead,
/// so that « Connexion requise » is not mistaken for « Hors connexion ».
class AccessHttpClient extends http.BaseClient {
  final http.Client _inner; final AccessManager access;
  AccessHttpClient({http.Client? inner,AccessManager? access}):_inner=inner??http.Client(),access=access??AccessManager.instance;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(access.headersFor(request.url));
    final response=await _inner.send(request);
    // Redirections are followed: a call that ends on the Cloudflare sign-in
    // page (or is refused by Access) did not reach SARCADE.
    final landed=response is http.BaseResponseWithUrl?response.url:null;
    if(isAccessChallenge(response.statusCode,response.headers)||(landed!=null&&isAccessPage(landed))){
      access.markRequired(request.url);
      await response.stream.drain<void>();
      throw AccessRequiredException(accessOrigin(request.url.toString()));
    }
    if(response.statusCode<500)access.markOk(request.url);
    return response;
  }

  @override void close()=>_inner.close();
}
