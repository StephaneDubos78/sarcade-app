import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/map_view.dart';
import 'package:sarcade_app/src/ui/theme.dart';

void main() {
  test('scale bar: round distances within the width', () {
    final s = scaleBar(15, 48.8);
    expect([1, 2, 5].any((f) => s.meters / f == (s.meters / f).roundToDouble()), isTrue);
    expect(s.px, lessThanOrEqualTo(110));
    expect(s.px, greaterThan(40));
    expect(scaleBar(8, 48.8).label, endsWith('km'));
    expect(scaleBar(18, 48.8).label, endsWith('m'));
  });
  test('last view kept and read back', () {
    final v = decodeView(encodeView(48.82312, 1.90941, 14.5))!;
    expect(v.lat, closeTo(48.82312, 1e-5));
    expect(v.zoom, 14.5);
    expect(decodeView('x'), isNull);
    expect(decodeView('95,1,10'), isNull);
  });
  test('links counted when used', () {
    expect(linksCount([true, true, null, false]), (ok: 2, total: 3));
  });
  test('theme mode names', () {
    expect(themeModeFrom(null), ThemeMode.dark);
    expect(themeModeFrom(themeModeName(ThemeMode.light)), ThemeMode.light);
    expect(nightTheme().colorScheme.brightness, Brightness.dark);
  });
}
