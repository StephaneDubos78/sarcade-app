import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/point_menu.dart';
import 'package:sarcade_app/src/operations/event_settings.dart';

// Card « Séparer le Core et les modules », step 2 (31 Oct 2026).
void main() {
  test('older servers and events: ADRASEC on', () {
    expect(const EventSettings().moduleOn('adrasec'), isTrue);
    expect(EventSettings.fromHeartbeat({'settings': {}}).modules, ['adrasec']);
  });

  test('modules read from the heartbeat', () {
    final family = EventSettings.fromHeartbeat({'settings': {'modules': []}});
    expect(family.moduleOn('adrasec'), isFalse);
    final race = EventSettings.fromHeartbeat({'settings': {'modules': ['race']}});
    expect(race.moduleOn('race'), isTrue);
    expect(race.moduleOn('adrasec'), isFalse);
  });

  test('point menu: « Relevé » only with ADRASEC', () {
    expect(pointMenuEntries(pco: false), contains(PointAction.bearing));
    expect(pointMenuEntries(pco: false, adrasec: false), isNot(contains(PointAction.bearing)));
    expect(pointMenuEntries(pco: false, adrasec: false), contains(PointAction.measure));
  });
}
