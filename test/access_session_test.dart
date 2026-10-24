import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/access/access_session.dart';

String jwt(Map<String,dynamic> claims){
  String part(Map<String,dynamic> m)=>base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=','');
  return '${part({'alg':'RS256'})}.${part(claims)}.c2ln';
}

void main(){
  final exp=DateTime.utc(2026,11,22,10);
  final token=jwt({'email':'stephane@example.org','exp':exp.millisecondsSinceEpoch~/1000});

  test('reads email and expiry of the Access token',(){
    final s=AccessSession.fromToken(' $token\n')!;
    expect(s.email,'stephane@example.org');
    expect(s.expiresAt,exp);
    expect(s.token,token);
  });

  test('refuses what is not a token',(){
    expect(AccessSession.fromToken('bonjour'),isNull);
    expect(AccessSession.fromToken('a.b.c<script>'),isNull);
    expect(AccessSession.fromToken('a.%%%.c'),isNull);
  });

  test('reminder 24 h before the end, then expired',(){
    final s=AccessSession.fromToken(token)!;
    expect(s.renewSoon(exp.subtract(const Duration(hours:25))),isFalse);
    expect(s.renewSoon(exp.subtract(const Duration(hours:23))),isTrue);
    expect(s.expired(exp.subtract(const Duration(minutes:1))),isFalse);
    expect(s.expired(exp),isTrue);
    expect(s.renewSoon(exp),isFalse);
  });

  test('token sent as header and cookie',(){
    final h=AccessSession.fromToken(token)!.headers;
    expect(h['cf-access-token'],token);
    expect(h['cookie'],'CF_Authorization=$token');
  });

  test('one session per server: scheme, host and port',(){
    expect(accessOrigin('https://App.Sarcade.org/'),'https://app.sarcade.org');
    expect(accessOrigin('https://app.sarcade.org/api/v0.1/sync'),'https://app.sarcade.org');
    expect(accessOrigin('http://192.168.0.110:8000'),'http://192.168.0.110:8000');
    expect(accessOrigin('https://app.sarcade.org')==accessOrigin('http://192.168.0.110:8000'),isFalse);
  });

  test('recognises Cloudflare Access instead of SARCADE',(){
    expect(isAccessChallenge(302,{'location':'https://sdubos.cloudflareaccess.com/cdn-cgi/access/login/app.sarcade.org?x=1'}),isTrue);
    expect(isAccessChallenge(302,{'location':'https://app.sarcade.org/cdn-cgi/access/login'}),isTrue);
    expect(isAccessChallenge(301,{'location':'https://app.sarcade.org/api/v0.1/sync'}),isFalse);
    expect(isAccessChallenge(403,{'cf-access-domain':'app.sarcade.org'}),isTrue);
    expect(isAccessChallenge(401,{'www-authenticate':'Cloudflare-Access domain=app.sarcade.org'}),isTrue);
    expect(isAccessChallenge(404,{}),isFalse);
    expect(isAccessChallenge(403,{'content-type':'application/json'}),isFalse);
    expect(isAccessPage(Uri.parse('https://sdubos.cloudflareaccess.com/cdn-cgi/access/login/x')),isTrue);
    expect(isAccessPage(Uri.parse('https://app.sarcade.org/api/v0.1/events')),isFalse);
  });
}
