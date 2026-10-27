import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/compass_follow.dart';

void main() {
  test('three modes of the button', () {
    expect(nextMeMode(MeMode.off, centred: false), MeMode.off);
    expect(nextMeMode(MeMode.off, centred: true), MeMode.follow);
    expect(nextMeMode(MeMode.follow, centred: true), MeMode.compass);
    expect(nextMeMode(MeMode.compass, centred: true), MeMode.follow);
  });
  test('heading smoothed across north', () {
    expect(smoothHeading(null, 370), 10);
    expect(smoothHeading(350, 10, fraction: 0.5), 0);
    expect(smoothHeading(10, 350, fraction: 0.5), 0);
    expect(smoothHeading(90, 100, fraction: 1), 100);
  });
  test('small changes ignored', () {
    expect(headingChanged(null, 10), isTrue);
    expect(headingChanged(359, 0.5), isFalse);
    expect(headingChanged(10, 20), isTrue);
  });
}
