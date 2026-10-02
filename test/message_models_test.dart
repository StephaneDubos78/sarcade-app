import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/message.dart';

void main(){
 test('message parses protocol payload',(){
  final m=SarcadeMessage.fromJson({'id':'m1','event_id':'e1','sender_id':'u1','recipient_ids':[],'priority':'urgent','body':'Besoin renfort','created_at':'2026-10-02T00:00:00Z'});
  expect(m.priority,'urgent'); expect(m.body,'Besoin renfort');
 });
 test('ack round trip',(){
  final a=SarcadeAck(id:'a1',eventId:'e1',messageId:'m1',actorId:'u2',status:'read',time:DateTime.utc(2026,10,2));
  expect(SarcadeAck.fromJson(a.toJson()).status,'read');
 });
}
