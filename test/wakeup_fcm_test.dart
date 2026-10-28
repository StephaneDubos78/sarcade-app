import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/services/wakeup_fcm.dart';

void main() {
  test('wake-up notification without content, channel by priority', () {
    expect(wakeTitle({'type': 'wake', 'priority': 'immediate'}), 'SARCADE : message prioritaire');
    expect(wakeTitle({'type': 'wake', 'priority': 'routine'}), 'SARCADE : nouveau message');
    expect(wakeTitle({'type': 'wake', 'kind': 'test', 'priority': 'immediate'}), 'SARCADE : réveil reçu');
    expect(wakeChannel({'priority': 'immediate'}), 'sarcade_immediate');
    expect(wakeChannel({'priority': 'urgent'}), 'sarcade_urgent');
    expect(wakeChannel({}), 'sarcade_routine');
  });

  test('no Firebase without the build-time project', () {
    expect(fcmAvailable, isFalse);
  });
}
