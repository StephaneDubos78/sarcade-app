import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversations.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage msg(String id, String from, List<String> to, int min) => SarcadeMessage(id: id, eventId: 'e', senderId: from,
    recipientIds: to, priority: 'routine', body: id, createdAt: DateTime.utc(2026, 10, 29, 10, min));

void main() {
  final tous = CommGroup(id: 't', eventId: 'e', name: 'Tous', kind: 'all', createdBy: 'PCO', updatedBy: 'PCO', updatedAt: DateTime.utc(2026));
  final pco = CommGroup(id: 'p', eventId: 'e', name: 'Diffusion PCO', kind: 'default', createdBy: 'PCO', updatedBy: 'PCO', updatedAt: DateTime.utc(2026));
  final by = {'t': tous, 'p': pco};

  test('broadcast and « Tous » are one conversation', () {
    expect(conversationOf(msg('1', 'PCO', [], 1), 'TEL', by), allKey);
    expect(conversationOf(msg('2', 'PCO', ['group:t'], 1), 'TEL', by), allKey);
    expect(conversationOf(msg('3', 'PCO', ['group:p'], 1), 'TEL', by), groupKey('p'));
  });

  test('a direct chat is the other person, both ways', () {
    expect(conversationOf(msg('1', 'TEL', ['user:PCO'], 1), 'TEL', by), directKey('PCO'));
    expect(conversationOf(msg('2', 'PCO', ['TEL'], 1), 'TEL', by), directKey('PCO'));
    expect(conversationOf(msg('3', 'PCO', ['user:TEL'], 1), 'TEL', by), directKey('PCO'));
  });

  test('what is written goes to the open conversation', () {
    expect(recipientsFor(allKey, by), isEmpty);
    expect(recipientsFor(groupKey('p'), by), ['group:p']);
    expect(recipientsFor(directKey('PCO'), by), ['user:PCO']);
  });

  test('direct chats, most recent first', () {
    final list = [msg('1', 'A', ['user:TEL'], 1), msg('2', 'TEL', ['user:B'], 5), msg('3', 'PCO', [], 9)];
    expect(directPeers(list, 'TEL', by), ['B', 'A']);
  });

  test('acknowledgement summary: read and received, sender left out', () {
    SarcadeAck a(String who, String s) => SarcadeAck(id: '$who$s', eventId: 'e', messageId: 'm', actorId: who, status: s, time: DateTime.utc(2026));
    expect(ackSummary('PCO', [a('A', 'received'), a('A', 'read'), a('B', 'received'), a('PCO', 'read')]), (read: 1, received: 2));
  });
}
