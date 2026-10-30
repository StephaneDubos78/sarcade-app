import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_aim.dart';
import 'package:sarcade_app/src/features/bearings/bearing_models.dart';
import 'package:sarcade_app/src/features/compass/compass_reading.dart';
import 'package:sarcade_app/src/features/compass/shared_compass.dart';

/// Card « Boussole instable » (30 Oct 2026): heading of the system, smoothed
/// without a jump across north, accuracy and calibration.
void main() {
  test('circular mean across north, spread in degrees', () {
    final a = circularStats([359, 1])!;
    expect((a.mean + 180) % 360 - 180, closeTo(0, 1e-6));
    expect(a.spread, closeTo(1, 0.05));
    expect(circularStats([10, 10, 10])!.spread, closeTo(0, 1e-6));
    expect(circularStats(const []), isNull);
    expect(circularStats([350, 10])!.spread, closeTo(10, 0.2));
  });

  test('smoothing over 0.5 s, older readings forgotten', () {
    final s = HeadingSmoother();
    final t = DateTime.utc(2026, 10, 30, 3);
    expect(s.add(t, 358), closeTo(358, 1e-6));
    final m = s.add(t.add(const Duration(milliseconds: 200)), 2)!;
    expect((m + 180) % 360 - 180, closeTo(0, 1e-6));
    expect(s.add(t.add(const Duration(seconds: 2)), 90), closeTo(90, 1e-6));
  });

  test('calibration asked when the accuracy is low', () {
    expect(compassNeedsCalibration(10, 3), isFalse);
    expect(compassNeedsCalibration(30, -1), isTrue);
    expect(compassNeedsCalibration(null, 1), isTrue);
    expect(compassNeedsCalibration(null, -1), isFalse);
  });

  test('one source for every user, stopped after the last one', () {
    var opened = 0;
    final source = StreamController<CompassReading>.broadcast();
    final c = SharedCompass(open: () {opened++; return source.stream;});
    expect(c.start(), isTrue);
    expect(c.start(), isTrue);
    expect(opened, 1);
    c.push(const CompassReading(120, accuracyDeg: 8, status: 3));
    expect(c.heading, closeTo(120, 1e-6));
    expect(c.calibrate, isFalse);
    c.push(const CompassReading(null));
    expect(c.calibrate, isTrue);
    c.stop();
    expect(c.heading, isNotNull);
    c.stop();
    expect(c.heading, isNull);
    final none = SharedCompass(open: () => null);
    expect(none.start(), isFalse);
    source.close();
  });

  test('« Modifier » with the mouse: same origin, tip on the saved azimuth', () {
    final t = DateTime.utc(2026, 10, 30, 1);
    final b = Bearing(id: 'b1', eventId: 'e', origin: const LatLng(48.8, 2.1), azimuthDeg: 123, lengthM: 8000, search: 's',
        takenAt: t, createdBy: 'T1', updatedBy: 'T1', updatedAt: t);
    final a = BearingAim.edit(b);
    expect(a.origin, b.origin);
    expect(a.azimuthDeg, 123);
    expect(a.fixed, isTrue);
    a.type(130);
    final e = a.edited(strength: 4, search: 's', exercise: false, lengthM: 10000, by: 'PCO', at: t.add(const Duration(minutes: 5)))!;
    expect(e.id, 'b1');
    expect(e.createdBy, 'T1');
    expect(e.azimuthDeg, 130);
    expect(e.lengthM, 10000);
    expect(e.takenAt, t);
    expect(BearingAim(b.origin).edited(strength: 0, search: '', exercise: false, lengthM: 1, by: 'x', at: t), isNull);
  });
}
