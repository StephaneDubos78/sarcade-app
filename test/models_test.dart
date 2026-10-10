import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/position.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  test('position JSON fields',(){
    final p=SarcadePosition.fromJson({'id':'p1','event_id':'e1','device_id':'d1','lat':48.8,'lon':2.1,'time':'2026-10-02T00:00:00Z'});
    expect(p.eventId,'e1');
    expect(p.toJson()['device_id'],'d1');
    expect(p.isAprs,isFalse);
    expect(p.toJson().containsKey('source'),isFalse);
  });

  test('APRS stations: callsign shown, source kept in the cache',(){
    final station=SarcadePosition.fromJson({'id':'p2','event_id':'e1','device_id':'aprs:F4ABC-9','lat':48.8,'lon':2.1,
      'time':'2026-10-10T08:00:00Z','source':'aprs','callsign':'F4ABC-9','aprs_via':'rf'});
    expect(station.isAprs,isTrue);
    expect(station.label,'F4ABC-9');
    expect(SarcadePosition.fromJson(station.toJson()).aprsVia,'rf');
    final linked=SarcadePosition.fromJson({'id':'p3','event_id':'e1','device_id':'TEL-01','lat':48.8,'lon':2.1,
      'time':'2026-10-10T08:00:00Z','source':'aprs','callsign':'F4ABC-7'});
    expect(linked.label,'TEL-01');
  });

  test('tool names follow the language',(){
    S.setLanguage('en');
    expect(FeatureKind.arrow.label,'Arrow');
    S.setLanguage('fr');
    expect(FeatureKind.arrow.label,'Flèche');
  });
}
