import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/operations/event_settings.dart';

void main(){
  test('settings from the heartbeat, with defaults for older servers',(){
    final s=EventSettings.fromHeartbeat({'settings':{'low_bandwidth':true,'low_bandwidth_interval_s':90,
      'tracking_min_interval_s':30,'tracking_max_interval_s':300},'tracking_required':true,'ended_at':null});
    expect(s.lowBandwidth,isTrue);
    expect(s.lowBandwidthIntervalS,90);
    expect(s.syncAlertMinutes,5);
    expect(s.trackingRequired,isTrue);
    expect(s.eventEnded,isFalse);
    expect(s.allowedIntervals,[30,60,120,300]);
    expect(s.clampInterval(10),30);
    expect(s.clampInterval(600),300);
    expect(EventSettings.fromHeartbeat(s.toJson()).lowBandwidth,isTrue);
  });

  test('end of the event',(){
    expect(EventSettings.fromHeartbeat({'settings':{},'ended_at':'2026-10-10T12:00:00Z'}).eventEnded,isTrue);
  });

  test('sync alert after the PCO threshold only',(){
    final now=DateTime.utc(2026,10,10,12,0);
    final ops=[{'client_time':'2026-10-10T11:57:00Z'},{'client_time':'2026-10-10T11:54:00Z'}];
    expect(syncAlert(ops,now,5),isNotNull);
    expect(syncAlert(ops,now,5)!.minutes,6);
    expect(syncAlert(ops,now,10),isNull);
    expect(syncAlert([],now,5),isNull);
  });

  test('urgent and immediate messages leave at once in low-bandwidth mode',(){
    expect(isUrgentOperation({'object_type':'message','payload':{'priority':'immediate'}}),isTrue);
    expect(isUrgentOperation({'object_type':'message','payload':{'priority':'urgent'}}),isTrue);
    expect(isUrgentOperation({'object_type':'message','payload':{'priority':'routine'}}),isFalse);
    expect(isUrgentOperation({'object_type':'position','payload':{}}),isFalse);
  });

  test('client update status and package',(){
    final u=ClientUpdate.fromJson({'status':'invited','min_version':'0.2.0','deadline':'2026-10-10T14:00:00Z',
      'package':{'platform':'windows','version':'0.2.1','sha256':'ab','url':'/api/v0.1/clients/windows/package'}});
    expect(u.status,UpdateStatus.invited);
    expect(u.targetVersion,'0.2.1');
    expect(u.packageUrl,'/api/v0.1/clients/windows/package');
    expect(ClientUpdate.fromJson({'status':'required','min_version':'0.2.0'}).targetVersion,'0.2.0');
    expect(ClientUpdate.fromJson(null).status,UpdateStatus.ok);
  });

  test('platform names and callsigns',(){
    expect(platformName(isWeb:true,targetPlatform:'android'),'web');
    expect(platformName(isWeb:false,targetPlatform:'iOS'),'ios');
    expect(packagePlatform('linux'),'appimage');
    expect(packagePlatform('web'),isNull);
    expect(validCallsign('f4abc-7'),isTrue);
    expect(validCallsign('F4 ABC'),isFalse);
  });
}
