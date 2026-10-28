import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_models.dart';
import 'package:sarcade_app/src/features/map/drawing/geometry.dart' as geo;

Bearing b(String id, LatLng o, double az, {String search = ''}) => Bearing(id: id, eventId: 'e', origin: o, azimuthDeg: az,
    search: search, takenAt: DateTime.utc(2026, 10, 27), createdBy: 'A', updatedBy: 'A', updatedAt: DateTime.utc(2026, 10, 27));

void main() {
  const target = LatLng(48.85, 1.95);
  final o1 = geo.destination(target, 3000, 200), o2 = geo.destination(target, 4000, 300), o3 = geo.destination(target, 2500, 90);
  final b1 = b('1', o1, geo.bearingDeg(o1, target)), b2 = b('2', o2, geo.bearingDeg(o2, target)), b3 = b('3', o3, geo.bearingDeg(o3, target));
  test('two bearings cross at the target', () {
    final c = crossing(b1, b2)!;
    expect(geo.distanceM(c, target), lessThan(30));
  });
  test('parallel or diverging bearings do not cross', () {
    expect(crossing(b('p', const LatLng(48.8, 1.9), 0), b('q', const LatLng(48.8, 1.95), 0)), isNull);
    expect(crossing(b('r', const LatLng(48.8, 1.9), 180), b('s', const LatLng(48.8, 1.95), 150)), isNull);
  });
  test('probable zone of three bearings', () {
    final z = probableZone([b1, b2, b3]);
    expect(z.crossings.length, 3);
    expect(geo.distanceM(z.centre!, target), lessThan(50));
    expect(z.radiusM, greaterThanOrEqualTo(50));
    expect(probableZone([b1]).centre, isNull);
  });
  test('JSON round trip and colour per search', () {
    final x = b('1', o1, 38.5, search: 'Balise 406');
    final y = Bearing.fromJson({...x.toJson(), 'created_by': 'A'});
    expect(y.azimuthDeg, 38.5);
    expect(y.search, 'Balise 406');
    expect(Bearing.isBearing(x.toJson()), isTrue);
    expect(searchColor('Balise 406'), searchColor('Balise 406'));
    expect(x.canEdit('B', false), isFalse);
    expect(x.canEdit('B', true), isTrue);
  });
}
