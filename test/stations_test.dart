import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/stations.dart';
import 'package:sarcade_app/src/models/position.dart';

SarcadePosition pos(String id, {String source = 'device', String? via, DateTime? t, double lat = 48.8, double lon = 1.9}) =>
    SarcadePosition(id: id, eventId: 'e', deviceId: id, lat: lat, lon: lon, time: t ?? DateTime.utc(2026, 10, 27, 12),
        source: source, aprsVia: via);

void main() {
  final now = DateTime.utc(2026, 10, 27, 12, 30);
  test('freshness thresholds and labels', () {
    expect(freshness(now.subtract(const Duration(seconds: 40)), now), Freshness.fresh);
    expect(freshness(now.subtract(const Duration(minutes: 6)), now), Freshness.ageing);
    expect(freshness(now.subtract(const Duration(minutes: 14)), now), Freshness.stale);
    expect(freshness(now.subtract(const Duration(minutes: 14)), now, staleMin: 20), Freshness.ageing);
    expect(ageLabel(now.subtract(const Duration(seconds: 12)), now), '12\u00A0s');
    expect(ageLabel(now.subtract(const Duration(minutes: 6)), now), '6\u00A0min');
    expect(ageLabel(now.subtract(const Duration(hours: 3)), now), '3\u00A0h');
  });
  test('source of a position', () {
    expect(sourceOf(pos('a')), PositionSource.app);
    expect(sourceOf(pos('b', source: 'aprs', via: 'rf')), PositionSource.aprsRadio);
    expect(sourceOf(pos('c', source: 'aprs', via: 'is')), PositionSource.aprsInternet);
    expect(worksWithoutInternet(pos('b', source: 'aprs', via: 'rf')), isTrue);
  });
  test('APRS symbols with overlay', () {
    expect(aprsSymbol('/>').kind, 'car');
    expect(aprsSymbol('L&').overlay, 'L');
    expect(aprsSymbol('L&').kind, 'igate');
    expect(aprsSymbol(null).icon, Icons.settings_input_antenna);
    expect(aprsSymbol('/§').kind, 'station');
  });
  test('favourites first, nearest, clusters, trace window', () {
    expect(sortStations([pos('b'), pos('a'), pos('c')], {'c'}).map((p) => p.deviceId), ['c', 'a', 'b']);
    final n = nearest(const LatLng(48.8, 1.9), [pos('far', lat: 48.9), pos('near', lat: 48.801)], (p) => LatLng(p.lat, p.lon));
    expect(n.first.item.deviceId, 'near');
    final groups = clusterOnScreen([1.0, 10.0, 200.0], (x) => Offset(x, 0));
    expect(groups.map((g) => g.length), [2, 1]);
    final h = [pos('x', t: now.subtract(const Duration(hours: 3))), pos('y', t: now.subtract(const Duration(minutes: 20)))];
    expect(traceWithin(h, now, 1).single.deviceId, 'y');
    expect(parseFavourites(encodeFavourites({'b', 'a'})), {'a', 'b'});
  });
  test('link with the server: direct, slowed or cut', () {
    expect(serverLink(syncOk: true, realtime: true), ServerLink.direct);
    expect(serverLink(syncOk: true, realtime: false), ServerLink.slowed);
    expect(serverLink(syncOk: null, realtime: false), ServerLink.slowed);
    expect(serverLink(syncOk: false, realtime: true), ServerLink.cut);
  });
  test('sections by freshness: active, without news, old', () {
    final now = DateTime.utc(2026, 10, 29, 12);
    expect(sectionOf(now.subtract(const Duration(minutes: 9)), now), Section.active);
    expect(sectionOf(now.subtract(const Duration(minutes: 10)), now), Section.silent);
    expect(sectionOf(now.subtract(const Duration(minutes: 119)), now), Section.silent);
    expect(sectionOf(now.subtract(const Duration(hours: 2)), now), Section.old);
    expect(sectionOf(now.subtract(const Duration(hours: 1)), now, oldMin: 30), Section.old);
  });
}
