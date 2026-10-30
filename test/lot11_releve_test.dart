import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/bearings/bearing_mouse_hud.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('revue n° 12: azimuth typed without a compass', () {
    expect(parseAzimuth('45'), 45);
    expect(parseAzimuth('045'), 45);
    expect(parseAzimuth('45,5°'), 45.5);
    expect(parseAzimuth('360'), 0);
    expect(parseAzimuth('361'), isNull);
    expect(parseAzimuth('abc'), isNull);
    expect(S.t('bearings.title'), 'Relevé');
    expect(S.t('bearings.azimuthHint'), 'ex. 045');
  });

  testWidgets('revue n° 12: « Relevé » with a visible « Azimut (°) » field', (tester) async {
    double? typed;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TypedBearingHud(position: null, accuracyM: null, time: DateTime(2026),
      onAzimuth: (d) => typed = d, onClose: () {}, decoration: const BoxDecoration()))));
    expect(find.text('Relevé'), findsOneWidget);
    expect(find.text('Azimut (°)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bearing-typed-azimuth')), '045');
    expect(typed, 45);
  });

  testWidgets('compass: compact line, help in the ⓘ, no capitals', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MouseBearingHud(trueDeg: 348, magneticDeg: 346, position: null, accuracyM: null,
      time: DateTime(2026), onClose: () {}, decoration: const BoxDecoration(), help: S.t('bearings.aimHelp')))));
    expect(find.text('348°'), findsOneWidget);
    expect(find.textContaining('VISEZ'), findsNothing);
    expect(find.byTooltip('Visez la source avec le haut du téléphone'), findsOneWidget);
  });
}
