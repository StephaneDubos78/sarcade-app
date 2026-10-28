import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/models/message_status.dart';

SarcadeAck ack(String actor, String status) => SarcadeAck(id: '$actor-$status', eventId: 'e', messageId: 'm',
    actorId: actor, status: status, time: DateTime.utc(2026, 10, 26));
SarcadeMessage msg(String id, String sender) => SarcadeMessage(id: id, eventId: 'e', senderId: sender,
    recipientIds: const [], priority: 'routine', body: id, createdAt: DateTime.utc(2026, 10, 26));

void main() {
  test('ticks: pending, sent, received, read', () {
    expect(sentStatus(pending: true, senderId: 'PCO', acks: [ack('A', 'read')]), SentStatus.pending);
    expect(sentStatus(pending: false, senderId: 'PCO', acks: []), SentStatus.sent);
    expect(sentStatus(pending: false, senderId: 'PCO', acks: [ack('PCO', 'read')]), SentStatus.sent);
    expect(sentStatus(pending: false, senderId: 'PCO', acks: [ack('A', 'received')]), SentStatus.received);
    expect(sentStatus(pending: false, senderId: 'PCO', acks: [ack('A', 'received'), ack('B', 'accepted')]), SentStatus.read);
  });
  test('readers counted once each', () {
    expect(readersCount('PCO', [ack('A', 'read'), ack('A', 'accepted'), ack('B', 'received'), ack('C', 'rejected')]), 2);
  });
  test('automatic read once, never for own messages', () {
    expect(needsAutoRead(message: msg('m', 'PCO'), deviceId: 'A', acks: [ack('A', 'received')]), isTrue);
    expect(needsAutoRead(message: msg('m', 'PCO'), deviceId: 'A', acks: [ack('A', 'accepted')]), isFalse);
    expect(needsAutoRead(message: msg('m', 'A'), deviceId: 'A', acks: []), isFalse);
  });
  test('opens on the first unread message, else at the bottom', () {
    final shown = [msg('1', 'B'), msg('2', 'B'), msg('3', 'B')];
    expect(firstUnreadIndex(shown, {'3', '2'}), 1);
    expect(firstUnreadIndex(shown, {}), isNull);
  });
}
