/// Cloudflare Access session of a server (« Accès protégé par Cloudflare
/// Access », decisions of 23 October 2026): pure helpers, testable without
/// Flutter.
library;

import 'dart:convert';

/// Reminder before the session ends (decision 2).
const renewBefore=Duration(hours:24);

/// Key of a server for its session: scheme, host and port, lower case.
String accessOrigin(String serverUrl){
  final u=Uri.tryParse(serverUrl.trim());
  if(u==null||u.host.isEmpty||!(u.scheme=='http'||u.scheme=='https'))return serverUrl.trim().toLowerCase();
  return u.origin.toLowerCase();
}

final _jwt=RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$');

/// Application token handed over by the server page, with what the
/// application shows: email and expiry. The signature is checked by
/// Cloudflare, not here.
class AccessSession {
  final String token; final String? email; final DateTime? expiresAt;
  const AccessSession({required this.token,this.email,this.expiresAt});

  /// Null when [raw] is not a JWT (pasted text, page content).
  static AccessSession? fromToken(String raw){
    final t=raw.trim();
    if(t.length>8192||!_jwt.hasMatch(t))return null;
    Map<String,dynamic> claims=const {};
    try{
      final part=base64Url.normalize(t.split('.')[1]);
      final decoded=jsonDecode(utf8.decode(base64Url.decode(part)));
      if(decoded is Map)claims=Map<String,dynamic>.from(decoded);
    }catch(_){return null;}
    final exp=claims['exp'];
    return AccessSession(token:t,email:claims['email'] as String?,
      expiresAt:exp is num?DateTime.fromMillisecondsSinceEpoch(exp.toInt()*1000,isUtc:true):null);
  }

  bool expired(DateTime now)=>expiresAt!=null&&!now.isBefore(expiresAt!);
  /// « Session SARCADE à renouveler »: less than 24 h left.
  bool renewSoon(DateTime now)=>expiresAt!=null&&!expired(now)&&expiresAt!.difference(now)<=renewBefore;

  /// Sent with every call to the protected server: the header that
  /// Cloudflare accepts from applications, and the browser cookie.
  Map<String,String> get headers=>{'cf-access-token':token,'cookie':'CF_Authorization=$token'};
}

/// True when Cloudflare Access answered instead of the SARCADE server:
/// redirection to the sign-in page, or refusal of a missing or expired token.
bool isAccessChallenge(int status,Map<String,String> headers){
  String h(String k)=>headers[k]??headers[k.toLowerCase()]??'';
  if(status>=300&&status<400){
    final loc=h('location').toLowerCase();
    return loc.contains('cloudflareaccess.com')||loc.contains('/cdn-cgi/access/');
  }
  if(status==401||status==403){
    if(h('www-authenticate').toLowerCase().contains('cloudflare-access'))return true;
    return headers.keys.any((k)=>k.toLowerCase().startsWith('cf-access'));
  }
  return false;
}

/// The sign-in page of Cloudflare Access (team domain or login path).
bool isAccessPage(Uri url)=>url.host.toLowerCase().endsWith('cloudflareaccess.com')||url.path.startsWith('/cdn-cgi/access/');

/// Raised when a call needs the Cloudflare Access sign-in: the server is
/// reachable, the operator must connect (« Connexion requise »).
class AccessRequiredException implements Exception {
  final String origin;
  const AccessRequiredException(this.origin);
  @override String toString()=>'access_required:$origin';
}
