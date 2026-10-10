import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/https_switch.dart';

void main(){
  test('from plain HTTP to the HTTPS address announced by the server',(){
    expect(httpsTarget('http://192.168.1.10:8000','https://adrasec78.sarcade.org/'),'https://adrasec78.sarcade.org');
    expect(httpsTarget('https://adrasec78.sarcade.org','https://adrasec78.sarcade.org'),isNull);
    expect(httpsTarget('https://other.example','https://adrasec78.sarcade.org'),isNull,reason:'already HTTPS: no switch');
    expect(httpsTarget('http://192.168.1.10:8000',null),isNull);
    expect(httpsTarget('http://192.168.1.10:8000','http://plain.example'),isNull);
    expect(httpsTarget('http://192.168.1.10:8000','nonsense'),isNull);
  });
}
