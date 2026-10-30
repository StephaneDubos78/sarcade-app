import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/files/drawings_section.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_layers.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_toolbar.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/comm_group.dart';
import 'package:sarcade_app/src/ui/color_palette.dart';

MapFeature shape(FeatureKind kind, List<LatLng> points) => MapFeature(id: kind.name, eventId: 'e', kind: kind, points: points,
    color: 0xFFE53935, strokeWidth: 4, createdBy: 'T1', updatedBy: 'T1', updatedAt: DateTime.utc(2026));

void main() {
  setUp(() => S.setLanguage('fr'));
  const a = LatLng(48.0, 2.0), b = LatLng(48.01, 2.01), d = LatLng(48.0, 2.02);

  test('points to add a vertex: lines and zones only', () {
    expect(sideMiddles(shape(FeatureKind.line, const [a, b, d])).length, 2);
    expect(sideMiddles(shape(FeatureKind.zone, const [a, b, d])).length, 3);
    expect(sideMiddles(shape(FeatureKind.arrow, const [a, b])), isEmpty);
    expect(sideMiddles(shape(FeatureKind.measure, const [a, b])), isEmpty);
  });

  test('an arrow is committed on the second tap, with 2 points', () {
    final c = DrawingController(eventId: 'e', actorId: 'T1');
    c.selectTool(FeatureKind.arrow);
    expect(c.tapAt(a), isNull);
    final f = c.tapAt(b);
    expect(f, isNotNull);
    expect(f!.points, const [a, b]);
    expect(FeatureKind.arrow.isMultiVertex, isFalse);
  });

  test('cursors: diagonal resize on the corners, « add » on the sides', () {
    expect(cornerCursor(const LatLng(49, 3), const LatLng(48, 2)), SystemMouseCursors.resizeUpRightDownLeft);
    expect(cornerCursor(const LatLng(49, 1), const LatLng(48, 2)), SystemMouseCursors.resizeUpLeftDownRight);
    expect(addVertexCursor, SystemMouseCursors.copy);
  });

  test('drawing toolbar without « Mesure »', () {
    expect(drawingToolbarKinds, isNot(contains(FeatureKind.measure)));
    expect(drawingToolbarKinds.length, FeatureKind.values.length - 1);
  });

  test('palette: 4 × 4, chosen colour added once', () {
    expect(drawingPalette.length, 16);
    expect(paletteWith(drawingPalette.first).length, 16);
    expect(paletteWith(0xFF123456).last, 0xFF123456);
    expect(paletteGridWidth(), 4 * 34 + 3 * 8);
  });

  test('drawings import / export: PCO and admin only', () {
    myActorId = 'T1';
    myRoles = <String>{};
    expect(canManageDrawings('T1'), isFalse);
    expect(canManageDrawings('PCO'), isTrue);
    myRoles = {'admin'};
    expect(canManageDrawings('T1'), isTrue);
    myRoles = <String>{};
    expect(S.t('files.drawings'), 'Dessins de l’événement');
    expect(S.t('files.importDrawings'), 'Importer des dessins');
    expect(S.t('files.exportDrawings'), 'Exporter les dessins');
  });

  testWidgets('tool labels on one line, same width', (tester) async {
    final c = DrawingController(eventId: 'e', actorId: 'T1');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawingToolbar(controller: c, onClose: () {}))));
    final w = tester.getSize(find.byKey(const ValueKey('draw-tool-rectangle'))).width;
    expect(tester.getSize(find.byKey(const ValueKey('draw-tool-point'))).width, w);
    expect(find.byKey(const ValueKey('draw-tool-measure')), findsNothing);
    final label = tester.widget<Text>(find.text(FeatureKind.rectangle.label));
    expect(label.maxLines, 1);
    await tester.binding.setSurfaceSize(null);
  });
}
