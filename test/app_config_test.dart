import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';

void main(){
  const env=AppConfig(serverUrl:'http://localhost:8000',eventId:'evt-demo',deviceId:'device-demo',tileUrl:'https://tiles/{z}/{x}/{y}.png',tileAttribution:'OSM');

  test('stored settings override operator fields and keep tile settings',(){
    final c=AppConfig.fromStored({'server_url':'http://192.168.1.20:8000','event_id':'evt-1','device_id':'TERRAIN-01'},env);
    expect(c.serverUrl,'http://192.168.1.20:8000');
    expect(c.eventId,'evt-1');
    expect(c.deviceId,'TERRAIN-01');
    expect(c.tileUrl,env.tileUrl);
    expect(c.tileAttribution,env.tileAttribution);
  });

  test('stored settings round-trip',(){
    final c=env.copyWith(deviceId:'TERRAIN-02');
    expect(AppConfig.fromStored(c.toStored(),env).sessionKey,c.sessionKey);
  });

  test('missing stored fields fall back to build-time values',(){
    expect(AppConfig.fromStored({'device_id':'TERRAIN-03'},env).serverUrl,env.serverUrl);
  });

  test('completeness requires server, event and terminal',(){
    expect(env.isComplete,isTrue);
    expect(env.copyWith(deviceId:' ').isComplete,isFalse);
  });
}
