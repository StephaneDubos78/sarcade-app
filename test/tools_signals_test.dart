import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_models.dart';
import 'package:sarcade_app/src/features/bearings/signals.dart';
import 'package:sarcade_app/src/features/tools/resection.dart';
import 'package:sarcade_app/src/models/reference_site.dart';

Bearing _b(String id, String search, int minute, {bool exercise = false, String by = 'T1'}) {
  final t = DateTime.utc(2026, 10, 29, 12, minute);
  return Bearing(id: id, eventId: 'e', origin: const LatLng(48.8, 2.1), azimuthDeg: 90, search: search,
      exercise: exercise, takenAt: t, createdBy: by, updatedBy: by, updatedAt: t);
}

ReferenceSite _site(String id, String name, double lat, double lon, {String category = 'HIGH_POINT'}) =>
    ReferenceSite(id: id, category: category, name: name, lat: lat, lon: lon, source: 's', sourceLayer: 'l', status: 'ok');

void main() {
  test('default signals: three frequencies, exercise beacon marked', () {
    expect(defaultSignals.map((s) => s.name), ['121,500 MHz · Balise de détresse réelle', '121,375 MHz · Balise d’exercice', '406,000 MHz · Cospas-Sarsat']);
    expect(defaultSignals.where((s) => s.exercise).length, 1);
  });

  test('frequency typed with a comma or a dot', () {
    expect(parseMhz('121,375'), 121.375);
    expect(parseMhz(' 145.500 MHz'), 145.5);
    expect(parseMhz('0'), isNull);
    expect(parseMhz('abc'), isNull);
  });

  test('menu: signals of the event first, then the visible defaults', () {
    final defaults = [...defaultSignals, const SignalChoice(label: 'Caché', frequencyMhz: 433.0, hidden: true)];
    final menu = signalMenu([_b('1', 'Balise 23/10', 1), _b('2', defaultSignals[1].name, 5, exercise: true)], defaults);
    expect(menu.first.name, defaultSignals[1].name);
    expect(menu.first.exercise, isTrue);
    expect(menu[1].name, 'Balise 23/10');
    expect(menu.map((s) => s.name), isNot(contains('433,000 MHz · Caché')));
    expect(menu.where((s) => s.name == defaultSignals[1].name).length, 1);
  });

  test('server list read back, built-in list when unreadable', () {
    final raw = encodeSignals([const SignalChoice(label: 'Test', frequencyMhz: 144.8, exercise: true)]);
    expect(decodeSignals(raw).single.exercise, isTrue);
    expect(decodeSignals('not json'), defaultSignals);
    expect(decodeSignals(null), defaultSignals);
  });

  test('bearing keeps exercise and frequency', () {
    final b = _b('1', 'x', 1, exercise: true).copyWith(frequencyMhz: 121.375, updatedBy: 'T1', updatedAt: DateTime.utc(2026));
    final again = Bearing.fromJson(b.toJson());
    expect(again.exercise, isTrue);
    expect(again.frequencyMhz, 121.375);
    expect(Bearing.fromJson(_b('2', 'y', 2).toJson()).toJson()['bearing'], isNot(contains('exercise')));
  });

  test('résection: narrow crossings detected', () {
    expect(crossingAngle(10, 30), 20);
    expect(crossingAngle(10, 190), 0);
    expect(crossingAngle(0, 90), 90);
    expect(crossingAngle(350, 20), 30);
  });

  test('résection: candidates filtered and sorted by distance', () {
    final sites = [_site('a', 'Mont Loin', 49.5, 2.0), _site('b', 'Relais Proche', 48.81, 2.1, category: 'RELAY'), _site('c', 'Butte', 48.9, 2.1)];
    final all = resectionCandidates(sites, around: const LatLng(48.8, 2.1));
    expect(all.map((e) => e.site.id), ['b', 'c', 'a']);
    expect(resectionCandidates(sites, around: const LatLng(48.8, 2.1), relays: false).map((e) => e.site.id), ['c', 'a']);
    expect(resectionCandidates(sites, query: 'butte').single.site.id, 'c');
  });

  test('résection controller: magnetic azimuth corrected, poor geometry flagged', () {
    final c = ResectionController()..around = const LatLng(48.8, 2.1);
    c.setKnown(0, const KnownPoint(point: LatLng(48.9, 2.1), label: 'A'));
    c.setKnown(1, const KnownPoint(point: LatLng(48.9, 2.15), label: 'B'));
    c.setAzimuth(0, 0);
    c.setAzimuth(1, 15);
    expect(c.validSights.length, 2);
    expect(c.poorGeometry, isTrue);
    c.setMagnetic(0, true);
    expect(c.trueAzimuth(c.sights[0]), closeTo((c.declination + 360) % 360, 1e-6)); // declination read at two instants
    c.dispose();
  });
}
