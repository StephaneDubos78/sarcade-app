import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/color_palette.dart';
import 'package:sarcade_app/src/ui/theme.dart';

void main() {
  test('revue n° 26: the black swatch keeps a light outline in the dark theme', () {
    final dark = swatchOutline(0xFF000000, Brightness.dark);
    expect(dark.color.computeLuminance(), greaterThan(0.3));
    expect(dark.width, 1.5);
    final light = swatchOutline(0xFFFFFFFF, Brightness.light);
    expect(light.color.computeLuminance(), lessThan(0.3));
    expect(swatchOutline(0xFF1A73E8, Brightness.light).width, 1);
  });

  test('revue n° 5, 45: map markers and scale in day colours on a light background', () {
    expect(mapMarkerScheme.brightness, Brightness.light);
    expect(mapInkBackground.computeLuminance(), greaterThan(0.8));
    expect(mapInkText.computeLuminance(), lessThan(0.1));
  });
}
