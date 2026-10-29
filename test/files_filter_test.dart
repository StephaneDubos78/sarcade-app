import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/shared_file.dart';

SarcadeSharedFile f(String id, String name, String folder, int day) => SarcadeSharedFile(id: id, eventId: 'e', senderId: 'PCO',
    name: name, mimeType: 'application/pdf', sizeBytes: 1, createdAt: DateTime.utc(2026, 10, day), folder: folder);

void main() {
  final all = [f('1', 'Plan relais.pdf', 'cartes', 1), f('2', 'Consigne SATER.pdf', 'consignes', 3), f('3', 'Divers.txt', 'divers', 2)];
  test('most recent first, by folder, by search', () {
    expect(filterFiles(all).map((x) => x.id), ['2', '3', '1']);
    expect(filterFiles(all, folder: 'cartes').map((x) => x.id), ['1']);
    expect(filterFiles(all, query: 'sater').map((x) => x.id), ['2']);
    expect(filterFiles(all, query: 'pco').length, 3);
  });
  test('unknown folder from an older server is « divers »', () {
    final x = SarcadeSharedFile.fromJson({'id': 'a', 'event_id': 'e', 'sender_id': 'P', 'name': 'n', 'created_at': '2026-10-29T00:00:00Z'});
    expect(x.folder, 'divers');
  });
}
