import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tv/tv_code.dart';

void main() {
  test('pairing code read from the QR link of the TV', () {
    expect(tvCodeFrom('https://app.sarcade.org/tv/approve?code=nflc2e'), 'NFLC2E');
    expect(tvCodeFrom('  b7qn8r '), 'B7QN8R');
    expect(tvCodeFrom('https://example.org/'), isNull);
    expect(tvCodeFrom('pas un code !'), isNull);
  });
}
