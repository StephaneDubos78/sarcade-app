import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/map/point_menu.dart';

void main() {
  const a = LatLng(48.80, 2.10), b = LatLng(48.81, 2.11);

  test('long press on an object selects it; closing ends the selection, the map moves again', () {
    final c = DrawingController(eventId: 'e', actorId: 'T1');
    c.selectTool(FeatureKind.arrow);
    c.tapAt(a);
    final f = c.tapAt(b)!;
    c.selectTool(null);
    c.startSelection(f.id);
    expect(c.selectMode, isTrue);
    expect(c.isSelected(f.id), isTrue);
    expect(c.locksMapDrag, isTrue);
    c.endSelection();
    expect(c.selectMode, isFalse);
    expect(c.hasSelection, isFalse);
    expect(c.locksMapDrag, isFalse);
  });

  test('« Sélectionner une zone » in the point menu', () {
    final c = DrawingController(eventId: 'e', actorId: 'T1');
    c.startSelection();
    expect(c.selectMode, isTrue);
    expect(c.hasSelection, isFalse);
    expect(c.tool, isNull);
    expect(pointMenuEntries(pco: false).last, PointAction.select);
  });
}
