import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/files/file_tree.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/models/shared_file.dart';

SarcadeSharedFile f(String id, String name, String folder, {String mime = 'application/pdf', int day = 1}) => SarcadeSharedFile(
    id: id, eventId: 'e', senderId: 'PCO', name: name, mimeType: mime, sizeBytes: 1, createdAt: DateTime.utc(2026, 10, day), folder: folder);

void main() {
  test('folders: parents and folders implied by files, « divers » at the root', () {
    final all = allFolders(['Procédures/Radio/VHF'], [f('1', 'a.pdf', 'cartes'), f('2', 'b.pdf', 'divers')]);
    expect(all, {'Procédures', 'Procédures/Radio', 'Procédures/Radio/VHF', 'cartes'});
    expect(childFolders(all, ''), ['cartes', 'Procédures']);
    expect(childFolders(all, 'Procédures'), ['Procédures/Radio']);
    expect(filesIn([f('1', 'a.pdf', 'cartes'), f('2', 'b.pdf', 'divers')], '').single.id, '2');
  });

  test('path helpers and names', () {
    expect(folderDepth(''), 0);
    expect(folderDepth('A/B/C'), 3);
    expect(parentFolder('A/B'), 'A');
    expect(joinFolder('', 'A'), 'A');
    expect(breadcrumb('Personnel', 'A/B').map((c) => c.path), ['', 'A', 'A/B']);
    expect(validFolderName(' Radio '), 'Radio');
    expect(validFolderName('a/b'), isNull);
    expect(validFolderName('..'), isNull);
    expect(validFolderName('x' * 61), isNull);
  });

  test('file colours by type', () {
    expect(fileKind(f('1', 'plan.pdf', '')).color.toARGB32(), 0xFFD93025);
    expect(fileKind(f('2', 'photo.jpg', '', mime: 'image/jpeg')).color.toARGB32(), 0xFF188038);
    expect(fileKind(f('3', 'trace.gpx', '', mime: 'application/octet-stream')).color.toARGB32(), 0xFFE8710A);
    expect(fileKind(f('4', 'note.txt', '', mime: 'text/plain')).color.toARGB32(), 0xFF1A73E8);
  });

  test('night between sunset and sunrise, sun events within the hour', () {
    // Versailles, 29 October 2026: sunset about 16:40 UTC.
    expect(isNightAt(DateTime.utc(2026, 10, 29, 12), 48.8, 2.13), isFalse);
    expect(isNightAt(DateTime.utc(2026, 10, 29, 20), 48.8, 2.13), isTrue);
    expect(isNightAt(DateTime.utc(2026, 10, 29, 3), 48.8, 2.13), isTrue);
    final set = sunTimes(DateTime.utc(2026, 10, 29), 48.8, 2.13).sunset!;
    final hour = DateTime.utc(set.year, set.month, set.day, set.hour);
    expect(sunEventIn(hour, 48.8, 2.13)?.kind, 'set');
    expect(sunEventIn(DateTime.utc(2026, 10, 29, 12), 48.8, 2.13), isNull);
  });
}
