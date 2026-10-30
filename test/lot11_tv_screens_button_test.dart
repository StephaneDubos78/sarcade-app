import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tv/tv_screens_button.dart';

void main() {
  final screens = <Map<String, dynamic>>[
    {'id': 'a', 'name': 'TV salle PCO', 'active': true, 'mine': true},
    {'id': 'b', 'name': 'Mur d’images', 'active': true, 'mine': false},
    {'id': 'c', 'name': 'Ancienne', 'active': false, 'mine': true},
    {'id': 'd', 'name': '', 'code': 'ABC123', 'active': true, 'mine': true},
  ];

  test('lot 11: the « Écrans » button lists my active screens, every active screen for the PCO', () {
    expect([for (final d in tvButtonScreens(screens, pco: false)) d['id']], ['d', 'a']);
    expect([for (final d in tvButtonScreens(screens, pco: true)) d['id']], ['d', 'b', 'a']);
    expect(tvButtonScreens(const [], pco: true), isEmpty);
    expect(tvScreenName(screens[3]), 'ABC123');
    expect(tvScreenName(screens[0]), 'TV salle PCO');
  });

  test('lot 11: connected when the TV asked less than 90 s ago', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
    expect(tvScreenConnected({'last_seen': 1000000 - 30}, now), isTrue);
    expect(tvScreenConnected({'last_seen': 1000000 - 91}, now), isFalse);
    expect(tvScreenConnected({'last_seen': null}, now), isFalse);
  });

  test('lot 11: « Suivre ma vue » sends at most every 2 s', () {
    final now = DateTime(2026, 10, 30, 18);
    expect(tvFollowWait(now, null), tvFollowDelay);
    expect(tvFollowWait(now, now.subtract(const Duration(milliseconds: 500))), const Duration(milliseconds: 1500));
    expect(tvFollowWait(now, now.subtract(const Duration(seconds: 10))), tvFollowDelay);
  });
}
