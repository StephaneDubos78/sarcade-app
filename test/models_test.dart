import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/position.dart';
void main(){test('position JSON fields',(){final p=SarcadePosition.fromJson({'id':'p1','event_id':'e1','device_id':'d1','lat':48.8,'lon':2.1,'time':'2026-10-02T00:00:00Z'});expect(p.eventId,'e1');expect(p.toJson()['device_id'],'d1');});}
