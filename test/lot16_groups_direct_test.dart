// Order of the channel chips and direct recipients (lot 16, 31 Oct 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/conversations.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/models/message.dart';

CommGroup g(String name, {String kind = 'default', List<String> members = const [], bool archived = false}) => CommGroup(
    id: name, eventId: 'e', name: name, kind: kind, members: members, archived: archived,
    createdBy: 'PCO', updatedBy: 'PCO', updatedAt: DateTime.utc(2026, 10, 31));

void main() {
  test('default channels in the fixed order, then teams, then the others', () {
    final list = [g('Logistique'), g('Zèbre', kind: 'custom'), g('Transmissions'), g('Équipe 2', kind: 'team'), g('PCO'),
      g('Équipes terrain'), g('Diffusion PCO'), g('Tous', kind: 'all'), g('Ancien', archived: true), g('Alpha', kind: 'custom')];
    expect(sortedGroups(list).map((x) => x.name),
        ['Tous', 'Diffusion PCO', 'PCO', 'Équipes terrain', 'Transmissions', 'Logistique', 'Équipe 2', 'Alpha', 'Zèbre']);
  });

  test('direct candidates: map, senders, members; not me nor APRS; PCO first', () {
    final positions = [
      {'event_id': 'e', 'device_id': 'TEL-02'},
      {'event_id': 'e', 'device_id': 'aprs:F4ABC-9', 'source': 'aprs'},
      {'event_id': 'other', 'device_id': 'TEL-99'},
      {'event_id': 'e', 'device_id': 'TEL-01'},
    ];
    final messages = [SarcadeMessage(id: 'm', eventId: 'e', senderId: 'PCO', recipientIds: const [], priority: 'routine', body: 'x',
        createdAt: DateTime.utc(2026, 10, 31))];
    final c = directCandidates(positions: positions, messages: messages, groups: [g('Binôme', kind: 'custom', members: ['TEL-05'])],
        eventId: 'e', me: 'TEL-01');
    expect(c, ['PCO', 'TEL-02', 'TEL-05']);
  });
}
