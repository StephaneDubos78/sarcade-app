import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/link_weather_pill.dart';
import 'package:sarcade_app/src/features/map/sos_placement.dart';
import 'package:sarcade_app/src/ui/map_view.dart';

void main() {
  const child = SizedBox(width: 48, height: 48);

  test('revue n° 15, 18, 32: SOS column never under a panel', () {
    final phone = mapColumnPlacement(compact: true, taking: false, card: false, bottom: 60, panel: true, child: child) as Positioned;
    expect(phone.top, 0);
    expect(phone.bottom, 0);
    final idle = mapColumnPlacement(compact: true, taking: false, card: false, bottom: 60, child: child) as Positioned;
    expect(idle.bottom, 60);
    expect(idle.top, isNull);
    final desk = mapColumnPlacement(compact: false, taking: true, card: false, bottom: 24, rightSheet: bearingSheetWidth, child: child) as Positioned;
    expect(desk.right, 12 + bearingSheetWidth + 12);
    expect(desk.bottom, 24);
  });

  test('revue n° 1, 3: the scale follows the zoom, above the ⓘ', () {
    // At zoom 15.5 (saved view) the scale is about 25 times shorter than at 11.
    expect(scaleBar(15.5, 48.8).meters < scaleBar(11, 48.8).meters / 10, isTrue);
    expect(mapScaleBottom(compact: true), greaterThan(mapAttributionLift));
    expect(mapScaleBottom(compact: false), greaterThan(0));
  });

  test('top bar on a phone: the temperature alone', () {
    expect(pillWeatherText(temperatureC: 13.6, wind: 'E 11 km/h', compact: true), '14°');
    expect(pillWeatherText(temperatureC: 13.6, wind: 'E 11 km/h', compact: false), '14° · E 11 km/h');
    expect(pillWeatherText(temperatureC: null, wind: null, compact: true), isNull);
    expect(pillTouch, greaterThanOrEqualTo(48));
  });

  testWidgets('revue n° 7: the link dot is a 48 px target', (tester) async {
    var links = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: LinkWeatherPill(dot: const Color(0xFF2E9D4B), linkTooltip: 'Liaison', onLinks: () => links++, onWeather: () {})))));
    final size = tester.getSize(find.byKey(const ValueKey('link-dot')));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const ValueKey('link-dot')));
    expect(links, 1);
  });
}
