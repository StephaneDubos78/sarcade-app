import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tv/tv_nearby.dart';

void main() {
  setUp(TvNearbyGate.reset);

  test('lot 11: no « Écran à proximité » while a scan or a pairing is open', () async {
    expect(TvNearbyGate.suspended, isFalse);
    TvNearbyGate.hold();
    expect(TvNearbyGate.suspended, isTrue);
    TvNearbyGate.release();
    expect(TvNearbyGate.suspended, isFalse);
    var seen = false;
    await TvNearbyGate.during(() async { seen = TvNearbyGate.suspended; });
    expect(seen, isTrue);
    expect(TvNearbyGate.suspended, isFalse);
    // Released even when the pairing fails.
    await expectLater(TvNearbyGate.during<void>(() async => throw StateError('x')), throwsStateError);
    expect(TvNearbyGate.suspended, isFalse);
    TvNearbyGate.release();
    expect(TvNearbyGate.suspended, isFalse);
  });

  test('lot 11: a scanned code is not offered again', () {
    final now = DateTime(2026, 10, 30, 18);
    expect(TvNearbyGate.toOffer(['abc123', 'DEF456'], now), ['ABC123', 'DEF456']);
    TvNearbyGate.handled('ABC123');
    expect(TvNearbyGate.toOffer(['ABC123', 'DEF456'], now), ['DEF456']);
  });

  test('lot 11: « Ignorer » keeps the same TV quiet for 5 minutes', () {
    final now = DateTime(2026, 10, 30, 18);
    TvNearbyGate.ignored('ABC123', now);
    expect(TvNearbyGate.toOffer(['ABC123'], now.add(const Duration(minutes: 4, seconds: 59))), isEmpty);
    expect(TvNearbyGate.toOffer(['ABC123'], now.add(const Duration(minutes: 5))), ['ABC123']);
  });
}
