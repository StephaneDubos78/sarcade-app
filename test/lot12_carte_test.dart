import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/operational_map_page.dart' show mapPanelOpen;

void main() {
  test('a window over the map is detected, so Back and « Carte » close it first', () {
    expect(mapPanelOpen(teams: false, reference: false, routes: false, resection: false, chat: false, desk: false), isFalse);
    expect(mapPanelOpen(teams: false, reference: false, routes: true, resection: false, chat: false, desk: false), isTrue);
    expect(mapPanelOpen(teams: false, reference: false, routes: false, resection: true, chat: false, desk: false), isTrue);
    expect(mapPanelOpen(teams: false, reference: false, routes: false, resection: false, chat: true, desk: false), isTrue);
    expect(mapPanelOpen(teams: false, reference: false, routes: false, resection: false, chat: false, desk: true), isTrue);
  });
}
