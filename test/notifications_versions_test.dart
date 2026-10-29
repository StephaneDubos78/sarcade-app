import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/operations/event_settings.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';

void main(){
  test('sound by priority: defaults, choices, SOS always the alarm',(){
    expect(soundFor('routine',{}),soundNormal);
    expect(soundFor('immediate',{}),soundAlarm);
    expect(soundFor('routine',{'routine':soundSilent}),soundSilent);
    expect(soundFor('urgent',{'urgent':soundSilent}),soundNormal);
    expect(soundFor('routine',{'routine':soundSilent},sos:true),soundAlarm);
    expect(isSosBody('🆘 DÉTRESSE — TEL — position 48, 2'),isTrue);
    expect(isSosBody('Fin de détresse — TEL'),isFalse);
  });

  test('store release read from the server and compared with this build',(){
    final u=ClientUpdate.fromJson({'status':'ok','latest':{'version':'0.2.0','build':415,'url':null}});
    expect(u.latest!.version,'0.2.0');
    expect(u.latest!.newerThan('0.1.0',''),isTrue);
    expect(u.latest!.newerThan('0.2.0','415'),isFalse);
    expect(u.latest!.newerThan('0.2.0','400'),isTrue);
    expect(u.latest!.newerThan('0.3.0-dev','1'),isFalse);
    expect(ClientUpdate.fromJson({'status':'ok'}).latest,isNull);
  });
}
