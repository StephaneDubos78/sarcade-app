import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/bearings/bearing_mouse_hud.dart';
import 'package:sarcade_app/src/features/map/drawing/hit_test.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

void main() {
  // 1 degree = 1000 px, north up.
  Offset project(LatLng p) => Offset(p.longitude * 1000, (49 - p.latitude) * 1000);
  final now = DateTime.utc(2026, 10, 31);
  final rect = MapFeature(id: 'r', eventId: 'e', kind: FeatureKind.rectangle,
      points: const [LatLng(48.9, 2.0), LatLng(48.8, 2.2)], color: 0xFF1A73E8, strokeWidth: 3, updatedAt: now);

  test('long press in the middle of a rectangle: point menu, the shape offered', () {
    final centre = project(const LatLng(48.85, 2.1));
    expect(hitOutline([rect], centre, project), isNull);
    expect(shapesUnder([rect], centre, project).single.id, 'r');
  });

  test('long press on the outline still selects the shape', () {
    final edge = project(const LatLng(48.9, 2.1)) + const Offset(0, 5);
    expect(hitOutline([rect], edge, project)?.id, 'r');
    final outside = project(const LatLng(48.95, 2.1));
    expect(hitOutline([rect], outside, project), isNull);
    expect(shapesUnder([rect], outside, project), isEmpty);
  });

  test('bearing origin in the middle of the visible part', () {
    const size = Size(390, 700);
    final phone = bearingFocus(size, phone: true);
    expect(phone.dx, 195);
    expect(phone.dy, lessThan(size.height / 2));
    final desk = bearingFocus(const Size(1200, 800), phone: false, rightSheetPx: 404);
    expect(desk.dx, (1200 - 404) / 2);
    // The map centre that puts the origin at the focus.
    LatLng unproject(Offset o) => LatLng(49 - o.dy / 1000, o.dx / 1000);
    const origin = LatLng(48.85, 2.1);
    final c = centreFor(origin, phone, size, project, unproject);
    final shift = project(origin) - project(c);
    expect(shift.dx, closeTo(phone.dx - size.width / 2, 1e-6));
    expect(shift.dy, closeTo(phone.dy - size.height / 2, 1e-6));
  });
}
