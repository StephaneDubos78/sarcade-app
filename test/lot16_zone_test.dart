// Robust probable zone (card « Zone probable : libellé trop gros et relevés
// incohérents », 31 Oct 2026). Same cases as tests/test_tv.py of the server.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_models.dart';
import 'package:sarcade_app/src/features/map/drawing/geometry.dart' as geo;

const target = LatLng(48.85, 1.95);

Bearing towards(String id, double distanceM, double from, {double offsetDeg = 0, String zone = 'auto'}) {
  final o = geo.destination(target, distanceM, from);
  return Bearing(id: id, eventId: 'e', origin: o, azimuthDeg: (geo.bearingDeg(o, target) + offsetDeg) % 360, zone: zone,
      search: 'Balise', takenAt: DateTime.utc(2026, 10, 31), createdBy: 'A', updatedBy: 'A', updatedAt: DateTime.utc(2026, 10, 31));
}

void main() {
  final good = [towards('1', 3000, 200), towards('2', 4000, 300), towards('3', 2500, 90)];

  test('three consistent bearings: zone on the target, none set aside', () {
    final z = probableZone(good);
    expect(z.bearings, 3);
    expect(z.excluded, isEmpty);
    expect(geo.distanceM(z.centre!, target), lessThan(60));
    expect(z.radiusM, greaterThanOrEqualTo(minZoneRadiusM));
  });

  test('a wild bearing is set aside automatically', () {
    final wild = towards('4', 3500, 20, offsetDeg: 40);
    final z = probableZone([...good, wild]);
    expect(z.excluded, ['4']);
    expect(z.autoExcluded, ['4']);
    expect(z.bearings, 3);
    expect(geo.distanceM(z.centre!, target), lessThan(60));
    expect(bearingZoneStatus(wild, [...good, wild]), contains('3'));
    expect(bearingZoneStatus(good.first, [...good, wild]), isNull);
  });

  test('kept by hand: never set aside', () {
    final wild = towards('4', 3500, 20, offsetDeg: 40, zone: 'in');
    final z = probableZone([...good, wild]);
    expect(z.excluded, isNot(contains('4')));
  });

  test('set aside by hand', () {
    final out = towards('3', 2500, 90, zone: 'out');
    final z = probableZone([good[0], good[1], out]);
    expect(z.excluded, ['3']);
    expect(z.autoExcluded, isEmpty);
    expect(z.bearings, 2);
  });

  test('nearly parallel bearings do not make a zone', () {
    final a = towards('a', 3000, 180), b = towards('b', 3000, 190);
    expect(probableZone([a, b]).centre, isNull);
    expect(probableZone([a, b], robust: false).centre, isNotNull);
  });

  test('rounded label', () {
    expect(roundedDistance(699), '700 m');
    expect(roundedDistance(1260), '1,3 km');
    expect(roundedDistance(12400), '12 km');
    expect(zoneLabel(700, 4, 1), '±700 m · 4 relevés · 1 écarté');
    expect(zoneLabel(1300, 3, 0), '±1,3 km · 3 relevés');
  });

  test('zone field round trip', () {
    final x = towards('1', 3000, 200, zone: 'out');
    final y = Bearing.fromJson({...x.toJson(), 'created_by': 'A'});
    expect(y.zone, 'out');
    expect(y.copyWith(zone: 'auto', updatedBy: 'B', updatedAt: DateTime.utc(2026, 11, 1)).zone, 'auto');
    expect(towards('2', 3000, 200).toJson().toString().contains('zone'), isFalse);
  });
}
