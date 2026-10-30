import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/messages_nav.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';
import 'package:sarcade_app/src/services/notification_keys.dart';
import 'package:sarcade_app/src/services/wakeup_fcm.dart';

void main() {
  test('distress key: same on the server, no callsign in it', () {
    expect(sosKey('ev1', 'PCO-demo'), 'sos-e520f6f9');
    expect(sosKey('ev1', 'PCO-demo').contains('PCO'), isFalse);
  });

  test('one notification per message, one per distress with its end', () {
    String key(String body, String priority, {List<String> to = const []}) => notificationKey(
        eventId: 'ev1', messageId: 'm1', senderId: 'PCO-demo', body: body, priority: priority, recipientIds: to);
    expect(key('Bonjour', 'routine'), 'm1');
    expect(key('🆘 DÉTRESSE — PCO-demo — position 48.1, 2.3', 'immediate'), 'sos-e520f6f9');
    expect(key('Fin de détresse — PCO-demo', 'urgent'), 'sos-e520f6f9');
    expect(key('End of distress — PCO-demo', 'urgent'), 'sos-e520f6f9');
    // Not a broadcast, or not immediate: an ordinary message.
    expect(key('🆘 DÉTRESSE', 'immediate', to: ['user:X']), 'm1');
    expect(key('🆘 test', 'routine'), 'm1');
  });

  test('the key travels with the payload', () {
    const p = NotificationPayload(eventId: 'e', messageId: 'm', deviceId: 'd', priority: 'immediate', key: 'sos-1');
    expect(NotificationPayload.decode(p.encode())!.key, 'sos-1');
    const q = NotificationPayload(eventId: 'e', messageId: 'm', deviceId: 'd', priority: 'routine');
    expect(NotificationPayload.decode(q.encode())!.key, 'm');
  });

  test('wake-up notification shares the identifier of the message', () {
    expect(wakeNotificationId({'type': 'wake', 'event_id': 'ev1', 'tag': 'm1'}), notificationIdFor('m1'));
    expect(wakeNotificationId({'type': 'wake', 'tag': 'sos-e520f6f9'}), 950687480);
    expect(wakeNotificationId({'type': 'wake', 'event_id': 'ev1'}), greaterThanOrEqualTo(90000));
  });

  test('drafts kept per conversation', () {
    final d = ConversationDrafts();
    d.keep('u:A', 'en cours');
    expect(d.take('u:A'), 'en cours');
    expect(d.take('all'), '');
    d.keep('u:A', '');
    expect(d.take('u:A'), '');
  });

  test('Messages pressed again: back to the list, then closed', () {
    final nav = MessagesNavigator();
    expect(nav.backToList(), isFalse);
    var open = true;
    bool back() { if (!open) return false; open = false; return true; }
    nav.attach(back);
    expect(nav.backToList(), isTrue);
    expect(nav.backToList(), isFalse);
    nav.detach(back);
    open = true;
    expect(nav.backToList(), isFalse);
  });
}
