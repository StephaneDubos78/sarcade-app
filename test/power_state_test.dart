import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/compass/compass_reading.dart';
import 'package:sarcade_app/src/features/compass/shared_compass.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/power_state.dart';

/// Card « iPhone, forte consommation de batterie » (30 Oct 2026, A to F).
void main(){
  test('Beacon interval: chosen when moving, 60 s still, 2 min power saving',(){
    expect(adaptiveIntervalS(10,moving:true,saver:false),10);
    expect(adaptiveIntervalS(10,moving:false,saver:false),60);
    expect(adaptiveIntervalS(300,moving:false,saver:false),300);
    expect(adaptiveIntervalS(10,moving:true,saver:true),120);
    expect(adaptiveIntervalS(600,moving:true,saver:true),600);
  });

  test('moving by speed or by distance beyond the accuracy',(){
    expect(isMoving(speedMps:1.2,distanceM:2,accuracyM:5),isTrue);
    expect(isMoving(speedMps:0,distanceM:10,accuracyM:5),isFalse);
    expect(isMoving(speedMps:0,distanceM:40,accuracyM:5),isTrue);
    expect(isMoving(speedMps:0,distanceM:40,accuracyM:60),isFalse);
    expect(isMoving(),isTrue);
    expect(isMoving(speedMps:0),isFalse);
  });

  test('TV check every 60 s, on screen, PCO only; no redraw in the background',(){
    final ticks=[for(var t=1;t<=90;t++)if(shouldPollTvNearby(t,foreground:true,pco:true))t];
    expect(ticks,[5,35,65]);
    expect(shouldPollTvNearby(5,foreground:false,pco:true),isFalse);
    expect(shouldPollTvNearby(5,foreground:true,pco:false),isFalse);
    expect(shouldRefreshUi(3,foreground:true,saver:false),isTrue);
    expect(shouldRefreshUi(3,foreground:true,saver:true),isFalse);
    expect(shouldRefreshUi(5,foreground:true,saver:true),isTrue);
    expect(shouldRefreshUi(5,foreground:false,saver:false),isFalse);
  });

  test('compass released in the background, read again on return',(){
    var opened=0;
    final c=SharedCompass(open:(){opened++;return const Stream<CompassReading>.empty();});
    expect(c.start(),isTrue); expect(c.running,isTrue);
    c.setPaused(true); expect(c.running,isFalse);
    c.setPaused(false); expect(c.running,isTrue); expect(opened,2);
    c.stop(); expect(c.running,isFalse);
    c.setPaused(true); c.setPaused(false); expect(c.running,isFalse);
  });

  test('« Consommation » line',(){
    S.setLanguage('fr');
    expect(consumptionLine(trackingS:null,moving:true,reduced:false,compass:false,saver:false,t:S.t),'GPS : suivi arrêté · boussole arrêtée');
    expect(consumptionLine(trackingS:60,moving:false,reduced:true,compass:true,saver:true,t:S.t),
      'GPS : suivi 1 min · à l’arrêt · précision réduite (arrière-plan) · boussole active · mode économie');
  });
}
