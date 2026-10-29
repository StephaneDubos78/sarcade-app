import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_aim.dart';
import 'package:sarcade_app/src/features/map/drawing/geometry.dart' as geo;

void main() {
  const o = LatLng(48.85, 2.35);
  test('azimuth from the origin to the mouse', () {
    expect(aimAzimuth(o, geo.destination(o, 3000, 73.4)), closeTo(73.4, 0.1));
    expect(aimAzimuth(o, geo.destination(o, 3000, 359.2)), closeTo(359.2, 0.1));
  });
  test('Shift snaps to 5 degrees', () {
    expect(snapDeg(72.4), 70);
    expect(snapDeg(72.6), 75);
    expect(snapDeg(358), 0);
    expect(snapDeg(-3), 355);
    expect(aimAzimuth(o, geo.destination(o, 3000, 73.4), snap: true), 75);
  });
  test('tip follows, is fixed, then taken again', () {
    final a = BearingAim(o);
    expect(a.follow(geo.destination(o, 1500, 40)), isTrue);
    expect(a.lengthM, closeTo(1500, 1));
    a.fix(geo.destination(o, 2500, 120.3), snap: true);
    expect(a.azimuthDeg, 120);
    expect(a.lengthM, closeTo(2500, 1));
    expect(a.follow(geo.destination(o, 900, 10)), isFalse);
    expect(a.azimuthDeg, 120);
    a.release();
    expect(a.follow(geo.destination(o, 900, 10)), isTrue);
    expect(a.azimuthDeg, closeTo(10, 0.1));
  });
  test('typed azimuth keeps the length', () {
    final a = BearingAim(o)..fix(geo.destination(o, 4000, 30));
    a.type(400);
    expect(a.azimuthDeg, 40);
    expect(a.lengthM, closeTo(4000, 1));
    expect(a.fixed, isTrue);
    final b = BearingAim(o)..type(90);
    expect(b.lengthM, closeTo(aimDefaultM, 1));
  });
  test('saved length comes back to the preference', () {
    expect(savedLengthM(), 10000);
    expect(savedLengthM(5000), 5000);
    expect(savedLengthM(0), 10000);
  });
  test('parse azimuth and click near the tip', () {
    expect(parseAzimuth('123,5°'), 123.5);
    expect(parseAzimuth('360'), 0);
    expect(parseAzimuth('400'), isNull);
    expect(parseAzimuth('abc'), isNull);
    expect(nearTip(const Offset(10, 10), const Offset(20, 15)), isTrue);
    expect(nearTip(const Offset(10, 10), const Offset(40, 10)), isFalse);
  });
}
