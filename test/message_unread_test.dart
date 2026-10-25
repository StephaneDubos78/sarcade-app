import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/models/message_unread.dart';

SarcadeMessage msg(String id,{String from='PCO',List<String> to=const [],String priority='routine'})=>SarcadeMessage(
  id:id,eventId:'e',senderId:from,recipientIds:to,priority:priority,body:id,createdAt:DateTime.utc(2026,10,25));

void main(){
  test('broadcast and direct messages from others are unread until seen',(){
    final all=[msg('a'),msg('b',to:['ADR78-01']),msg('c',to:['ADR78-02']),msg('d',from:'ADR78-01')];
    final unread=unreadMessages(messages:all,seen:{'a'},deviceId:'ADR78-01',groups:{});
    expect(unread.map((m)=>m.id),['b']);
  });
  test('urgent or immediate turns the pastille red',(){
    expect(anyUrgent([msg('a')]),isFalse);
    expect(anyUrgent([msg('a'),msg('b',priority:'urgent')]),isTrue);
    expect(anyUrgent([msg('c',priority:'immediate')]),isTrue);
  });
  test('Enter sends on computers only',(){
    expect(enterSends('windows'),isTrue);
    expect(enterSends('linux'),isTrue);
    expect(enterSends('macOS'),isTrue);
    expect(enterSends('android'),isFalse);
    expect(enterSends('iOS'),isFalse);
  });
}
