import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/services/realtime_service.dart';

void main() {
  final t0 = DateTime(2026, 10, 26, 10);
  test('dead channel: 90 s of silence once the server answers pings', () {
    expect(RealtimeService.silent(t0.add(const Duration(seconds: 91)), t0, true), isTrue);
    expect(RealtimeService.silent(t0.add(const Duration(seconds: 60)), t0, true), isFalse);
  });
  test('a server without pong is never timed out', () {
    expect(RealtimeService.silent(t0.add(const Duration(hours: 1)), t0, false), isFalse);
  });
}
