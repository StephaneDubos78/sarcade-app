import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/message.dart';

void main() {
  final orig = SarcadeMessage(id: 'm1', eventId: 'e', senderId: 'TEL-01', recipientIds: const [], priority: 'routine',
      body: 'Véhicule repéré au carrefour', createdAt: DateTime.utc(2026, 10, 31, 1));

  test('a reply keeps the id of the quoted message', () {
    final r = SarcadeMessage(id: 'm2', eventId: 'e', senderId: 'TEL-02', recipientIds: const [], priority: 'routine',
        body: 'Bien reçu', createdAt: DateTime.utc(2026, 10, 31, 1, 2), replyTo: 'm1');
    final j = r.toJson();
    expect(j['reply_to'], 'm1');
    expect(SarcadeMessage.fromJson(j).replyTo, 'm1');
    expect(orig.toJson().containsKey('reply_to'), isFalse);
    expect(SarcadeMessage.fromJson({...orig.toJson(), 'reply_to': ''}).replyTo, isNull);
  });

  test('quote: author and start of the text, deleted or missing', () {
    var q = quoteOf(orig, deletedText: 'Message supprimé', photoText: 'Photo', missingText: 'Message introuvable');
    expect(q.author, 'TEL-01');
    expect(q.text, 'Véhicule repéré au carrefour');
    final gone = SarcadeMessage(id: 'm1', eventId: 'e', senderId: 'TEL-01', recipientIds: const [], priority: 'routine',
        body: '', createdAt: DateTime.utc(2026), deleted: true);
    q = quoteOf(gone, deletedText: 'Message supprimé', photoText: 'Photo', missingText: 'Message introuvable');
    expect(q.text, 'Message supprimé');
    expect(q.deleted, isTrue);
    q = quoteOf(null, deletedText: 'Message supprimé', photoText: 'Photo', missingText: 'Message introuvable');
    expect(q.text, 'Message introuvable');
    final long = SarcadeMessage(id: 'x', eventId: 'e', senderId: 'A', recipientIds: const [], priority: 'routine',
        body: 'a' * 200, createdAt: DateTime.utc(2026));
    expect(quoteOf(long, deletedText: '', photoText: '', missingText: '').text.length, 88);
  });
}
