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
  test('beacon colours: 406 violet, 121,5 red, exercise 121,375 blue', () {
    expect(searchColor('406,000 MHz · Cospas-Sarsat'), beacon406Color);
    expect(searchColor('Balise 406 – 23/10'), beacon406Color);
    expect(searchColor('121,500 MHz · Balise de détresse réelle'), beacon1215Color);
    expect(searchColor('121,375 MHz · Balise d’exercice'), beaconExerciseColor);
    expect(beaconColor('Relais 2026'), isNull);
  });
  test('« Signal recherché »: old target moved into the comment', () {
    final j = b('1', o1, 38.5, search: 'Balise 406').toJson();
    (j['bearing'] as Map)['target'] = '121,500 MHz';
    (j['bearing'] as Map)['comment'] = 'faible';
    final y = Bearing.fromJson(j);
    expect(y.search, 'Balise 406');
    expect(y.comment, '121,500 MHz · faible');
    expect(legacyComment('', 'x'), 'x');
    expect(legacyComment('A', 'A déjà'), 'A déjà');
  });
  test('signals of the event, most recent first, without duplicates', () {
    Bearing at(String id, String s, int min) => Bearing.fromJson({...b(id, o1, 10, search: s).toJson(),
      'bearing': {...(b(id, o1, 10, search: s).toJson()['bearing'] as Map), 'taken_at': DateTime.utc(2026, 10, 29, 10, min).toIso8601String()}});
    expect(signalsByRecency([at('1', 'A', 1), at('2', 'B', 5), at('3', 'A', 9), at('4', '', 12)]), ['A', 'B']);
  });
  test('operator colour and initials are stable', () {
    expect(operatorColor('F4JPO'), operatorColor('F4JPO'));
    expect(operatorInitials('f4jpo-7'), 'F4');
    expect(operatorInitials('PC'), 'PC');
  });
  test('résection: position from azimuths towards known points', () {
    const team = LatLng(48.80, 1.90);
    final a = geo.destination(team, 5000, 30), c = geo.destination(team, 7000, 150), d = geo.destination(team, 4000, 270);
    final r = resection([
      (known: a, azimuthDeg: geo.bearingDeg(team, a)),
      (known: c, azimuthDeg: geo.bearingDeg(team, c)),
      (known: d, azimuthDeg: geo.bearingDeg(team, d)),
    ]);
    expect(geo.distanceM(r.centre!, team), lessThan(60));
  });
  test('time of a bearing changed afterwards', () {
    final t = DateTime(2026, 10, 29, 9, 0).toUtc();
    expect(hhmm(withHhmm(t, '14:05')), '14:05');
    expect(hhmm(withHhmm(t, '14h05')), '14:05');
    expect(withHhmm(t, 'n’importe'), t);
  });
}
