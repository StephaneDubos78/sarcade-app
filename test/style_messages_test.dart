import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/version.dart';
import 'package:sarcade_app/src/features/map/stations.dart';
import 'package:sarcade_app/src/features/messages/conversations.dart';

void main() {
  test('date separators: today, yesterday, then the date', () {
    final now = DateTime(2026, 10, 29, 13, 20);
    String l(DateTime t) => dayLabel(t, now, today: 'Aujourd’hui', yesterday: 'Hier');
    expect(l(DateTime(2026, 10, 29, 0, 5)), 'Aujourd’hui');
    expect(l(DateTime(2026, 10, 28, 23, 59)), 'Hier');
    expect(l(DateTime(2026, 10, 27, 9)), '27/10/2026');
    expect(dayKey(DateTime(2026, 10, 29, 1)), dayKey(DateTime(2026, 10, 29, 23)));
  });

  test('platform shown as people say it', () {
    expect(platformLabel('android'), 'Android');
    expect(platformLabel('ios'), 'iPhone');
    expect(platformLabel('web'), 'Web');
    expect(platformLabel('other'), 'other');
  });

  test('version sent with the build number when the CI gives one', () {
    expect(appVersionFull.startsWith(appVersion), isTrue);
    expect(appVersionFull == appVersion || appVersionFull.contains('+'), isTrue);
  });
}
