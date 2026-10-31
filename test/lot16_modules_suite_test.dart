// Core and modules, step 2 (card « Séparer le Core et les modules »):
// event models offered to the PCO, same table as the server.
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/operations/event_settings.dart';

void main() {
  test('event models and their modules', () {
    expect(eventKinds, ['exercise', 'sater', 'mission', 'race', 'family', 'friends']);
    expect(modulesOfKind('family'), isEmpty);
    expect(modulesOfKind('friends'), isEmpty);
    for (final k in ['exercise', 'sater', 'mission']) {
      expect(modulesOfKind(k), ['adrasec']);
    }
    expect(modulesOfKind('race'), ['race']);
    expect(modulesOfKind('unknown'), ['adrasec']);
  });
  test('ADRASEC by default when the server does not say', () {
    expect(eventModules(null), ['adrasec']);
    expect(eventModules({'modules': <String>[]}), isEmpty);
  });
}
