import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_sheet.dart';
import 'package:sarcade_app/src/features/map/layer_row.dart';
import 'package:sarcade_app/src/features/map/locate_cycle.dart';
import 'package:sarcade_app/src/features/map/point_menu.dart';

/// Lot 2 « navigation et carte » (30 Oct 2026).
void main() {
  test('one position button: me, follow, compass, all operators, me', () {
    var m = LocateMode.idle;
    final seen = <LocateMode>[];
    for (var i = 0; i < 5; i++) { m = nextLocateMode(m); seen.add(m); }
    expect(seen, [LocateMode.me, LocateMode.follow, LocateMode.compass, LocateMode.all, LocateMode.me]);
    expect(nextLocateMode(LocateMode.follow, compass: false), LocateMode.all);
    expect(locateLabel(LocateMode.me), isNull);
    expect(locateLabel(LocateMode.all), isNotNull);
  });

  test('point menu: validated order, PCO entry only for the PCO', () {
    expect(pointMenuEntries(pco: true), [PointAction.bearing, PointAction.poi, PointAction.order,
      PointAction.measure, PointAction.navigate, PointAction.weather, PointAction.select]);
    expect(pointMenuEntries(pco: false).contains(PointAction.order), isFalse);
  });

  test('a press within 30 m of my position is a bearing from the GPS', () {
    const me = LatLng(48.8, 2.1);
    expect(nearOwnPosition(const LatLng(48.80018, 2.1), me), isTrue); // ≈ 20 m
    expect(nearOwnPosition(const LatLng(48.8009, 2.1), me), isFalse); // ≈ 100 m
    expect(nearOwnPosition(const LatLng(48.8, 2.1), null), isFalse);
  });

  test('one opacity per layer, started from the former group', () {
    final prefs = {'opacity:ops': '0.50', 'opacity:ref': '0.30', 'opacity:relay': '0.80'};
    double o(String k) => layerOpacityFrom((key) => prefs[key], k);
    expect(o('aprs'), 0.5);
    expect(o('high'), 0.3);
    expect(o('relay'), 0.8);
    expect(o('draw'), 1.0);
  });

  test('base map notices listed once each', () {
    final n = basemapNotices(builtInBasemaps);
    expect(n.where((x) => x.contains('IGN')).length, 1);
    expect(n.any((x) => x.contains('OpenStreetMap')), isTrue);
  });
}
