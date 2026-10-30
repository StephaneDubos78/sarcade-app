import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/fixed_stations.dart';
import 'package:sarcade_app/src/models/position.dart';

SarcadePosition aprs(String call, {String? symbol, double lat = 48.8, double lon = 2.1, DateTime? t, double? speed}) => SarcadePosition(
    id: '$call$lat', eventId: 'e', deviceId: 'aprs:$call', lat: lat, lon: lon, time: t ?? DateTime.utc(2026, 10, 30, 12),
    source: 'aprs', callsign: call, aprsSymbol: symbol, speedMps: speed);

void main() {
  test('symbol, SSID and forced classification', () {
    expect(isFixedStation(aprs('F1ABC', symbol: '/&')), isTrue); // iGate
    expect(isFixedStation(aprs('F1ABC', symbol: '/#')), isTrue); // digipeater
    expect(isFixedStation(aprs('F1ABC', symbol: '/_')), isTrue); // weather
    expect(isFixedStation(aprs('F1ABC', symbol: '/-')), isTrue); // house
    expect(isFixedStation(aprs('F1ABC-10')), isTrue);
    expect(isFixedStation(aprs('F1ABC-2')), isTrue);
    expect(isFixedStation(aprs('F1ABC-9', symbol: '/>')), isFalse);
    expect(isFixedStation(aprs('F1ABC-2', symbol: '/>')), isFalse); // a car stays mobile
    expect(isFixedStation(aprs('F1ABC-10'), forced: 'm'), isFalse);
    expect(isFixedStation(aprs('F1ABC-9', symbol: '/>'), forced: 'f'), isTrue);
    expect(isFixedStation(aprs('F1ABC-10'), moved: true), isFalse);
    expect(isFixedStation(aprs('F1ABC-7'), still: true), isTrue);
    expect(isFixedStation(SarcadePosition(id: 'x', eventId: 'e', deviceId: 'PCO', lat: 0, lon: 0, time: DateTime.utc(2026)), forced: 'f'), isFalse);
    expect(ssidOf('F4ABC-10'), 10);
    expect(ssidOf('F4ABC'), isNull);
  });

  test('movement over several hours', () {
    final m = MovementTracker();
    final t0 = DateTime.utc(2026, 10, 30, 8);
    m.observe(aprs('F1ABC-7', t: t0));
    m.observe(aprs('F1ABC-7', lat: 48.8002, t: t0.add(const Duration(hours: 1)))); // about 22 m
    expect(m.moved('aprs:F1ABC-7'), isFalse);
    expect(m.still('aprs:F1ABC-7', t0.add(const Duration(hours: 2))), isFalse);
    expect(m.still('aprs:F1ABC-7', t0.add(const Duration(hours: 3))), isTrue);
    m.observe(aprs('F1ABC-7', lat: 48.801, t: t0.add(const Duration(hours: 4)))); // about 110 m
    expect(m.moved('aprs:F1ABC-7'), isTrue);
    expect(m.still('aprs:F1ABC-7', t0.add(const Duration(hours: 5))), isFalse);
  });

  test('forced classifications kept on the device', () {
    final f = parseForced('aprs:A=f|aprs:B-2=m|bad|aprs:C=x');
    expect(f, {'aprs:A': 'f', 'aprs:B-2': 'm'});
    expect(encodeForced(f), 'aprs:A=f|aprs:B-2=m');
    expect(encodeForced({}), isNull);
  });
}
