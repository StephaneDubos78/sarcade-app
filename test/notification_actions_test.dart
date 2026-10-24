import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';

void main(){
  test('buttons by priority',(){
    expect(actionsFor('immediate'),[actionAccept,actionRefuse,actionOpen]);
    expect(actionsFor('urgent'),[actionAccept,actionRefuse,actionOpen]);
    expect(actionsFor('routine'),[actionRead,actionOpen]);
  });

  test('an action is an acknowledgement, Open only opens',(){
    expect(ackStatusForAction(actionAccept),'accepted');
    expect(ackStatusForAction(actionRefuse),'rejected');
    expect(ackStatusForAction(actionRead),'read');
    expect(ackStatusForAction(actionOpen),isNull);
    expect(ackStatusForAction(null),isNull);
    expect(stopsReminders('accepted')&&stopsReminders('rejected')&&stopsReminders('read'),isTrue);
    expect(stopsReminders('received'),isFalse);
  });

  test('payload survives the round trip, actions found on every platform',(){
    const p=NotificationPayload(eventId:'evt-1',messageId:'m-42',deviceId:'TEL-01',priority:'immediate');
    final back=NotificationPayload.decode(p.encode())!;
    expect([back.eventId,back.messageId,back.deviceId,back.priority],['evt-1','m-42','TEL-01','immediate']);
    expect(NotificationPayload.decode('nonsense'),isNull);
    expect(NotificationPayload.decode(null),isNull);
    // Android, iOS, Linux: action identifier given by the platform.
    expect(resolveAction('accept',p.encode()),actionAccept);
    // Windows: the arguments of the button come back as payload and action.
    expect(resolveAction(p.encode(actionRefuse),p.encode(actionRefuse)),actionRefuse);
    // Tap on the notification itself.
    expect(resolveAction(null,p.encode()),actionOpen);
    expect(resolveAction('',p.encode()),actionOpen);
  });

  test('stable notification identifiers below 2^31, one per reminder',(){
    final ids=[for(var k=0;k<=reminderCount;k++)notificationIdFor('8b0f6c1e-1d2a-4f00-9a77-0c1b2d3e4f50',k)];
    expect(ids.toSet().length,4);
    expect(ids.every((i)=>i>=0&&i<0x7fffffff),isTrue);
    expect(notificationIdFor('abc'),notificationIdFor('abc'));
    expect(notificationIdFor('abc')%4,0);
  });

  test('immediate messages reminded every 2 minutes, 3 times',(){
    final t0=DateTime.utc(2026,10,10,13);
    expect(reminderTimes(t0),[DateTime.utc(2026,10,10,13,2),DateTime.utc(2026,10,10,13,4),DateTime.utc(2026,10,10,13,6)]);
  });

  test('answers waiting in the file become acknowledgements',(){
    final a=PendingAnswer(id:'a1',eventId:'evt-1',messageId:'m-42',deviceId:'TEL-01',status:'accepted',time:DateTime.utc(2026,10,10,13,1));
    final lines='${a.toLine()}\n{broken\n${a.toLine()}\n';
    final parsed=PendingAnswer.parseLines(lines);
    expect(parsed.length,2);
    expect(parsed.first.toAck(),{'id':'a1','event_id':'evt-1','message_id':'m-42','actor_id':'TEL-01','status':'accepted',
      'time':'2026-10-10T13:01:00.000Z'});
  });
}
