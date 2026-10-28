import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/aprs/aprs_models.dart';

void main() {
  test('callsigns cleaned, with or without SSID', () {
    expect(cleanCallsign(' f4jpo '), 'F4JPO');
    expect(cleanCallsign('F4JPO-7'), 'F4JPO-7');
    expect(cleanCallsign('F4JPO-ABC'), isNull);
    expect(cleanCallsign('?'), isNull);
  });
  test('free text: the ADRASEC 78 list', () {
    final r = parseCallsigns('F4JPO F4HKS, f8bog\nF4HVQ;F4JPO bad!');
    expect(r.valid, ['F4JPO', 'F4HKS', 'F8BOG', 'F4HVQ']);
    expect(r.invalid, ['bad!']);
  });
  test('link state', () {
    expect(linkState(null), 'off');
    expect(linkState({'enabled': false}), 'off');
    expect(linkState({'enabled': true, 'connected': false}), 'waiting');
    expect(linkState({'enabled': true, 'connected': true}), 'connected');
  });
}
