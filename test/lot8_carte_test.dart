import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_layers.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';
import 'package:sarcade_app/src/features/map/drawing/multi_select.dart';
import 'package:sarcade_app/src/features/map/map_objects.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/offline/outbox_policy.dart';
import 'package:sarcade_app/src/offline/unsent_summary.dart';

const server = 'http://nas:8000';

Map<String, dynamic> op(String id, {String type = 'message', String action = 'create', Map<String, dynamic>? payload, String event = 'e1'}) => {
      'operation_id': id, 'event_id': event, 'object_id': 'o-$id', 'object_type': type, 'action': action,
      'client_time': '2026-10-30T09:00:00Z', 'payload': payload ?? {'body': 'texte'}, localKey: newLocal(server),
    };

/// Screen projection for the tests: 1° = 1000 px.
Offset project(LatLng p) => Offset(p.longitude * 1000, -p.latitude * 1000);

void main() {
  setUp(() => S.setLanguage('fr'));

  group('Fond et affichage', () {
    test('order: default label « Point de la carte »', () {
      expect(S.t('order.point'), 'Point de la carte');
    });
    test('« Voir la liste » hidden without any point', () {
      expect(poiSeeListLink(0, onTap: () {}), isNull);
      expect(poiSeeListLink(3, onTap: () {}), isNotNull);
    });
  });

  group('Non envoyés', () {
    test('the banner says what is blocked', () {
      final photo = op('a', payload: {'body': '', 'attachments': [{'file_id': 'f1'}]});
      expect(unsentWhat([photo]), '1 photo(s) non envoyée(s)');
      expect(unsentWhat([op('b'), op('c'), op('d', type: 'position')]), '2 message(s) non envoyé(s) · 1 position(s) non envoyée(s)');
      expect(unsentKind(op('e', type: 'message', action: 'delete')), 'delete');
      expect(unsentKind(op('f', type: 'map_feature', payload: {'kind': 'bearing'})), 'bearing');
      expect(unsentWhat(const []), '');
    });

    test('« Envoyer » = « Tout réessayer »: items set aside go back to the queue', () {
      final now = DateTime.utc(2026, 10, 30, 10);
      final aside = afterFailure(op('a'), now, status: 'rejected', reason: 'données invalides', setAside: true);
      final fresh = op('b');
      final other = afterFailure(op('c', event: 'e2'), now, status: 'rejected', setAside: true);
      // An ordinary batch leaves the item set aside out…
      expect(nextBatch([aside, fresh], server, 'e1', {}).map((o) => o['operation_id']), ['b']);
      // …« Tout réessayer » puts it back, not the item of another event.
      final again = retryAllOf([aside, fresh, other], server, 'e1', now);
      expect(again.map((o) => o['operation_id']), ['a']);
      expect(isSetAside(again.single), isFalse);
      expect(attempts(again.single), 0);
      expect(nextBatch(again, server, 'e1', {}).length, 1);
    });

    test('reason of the server in plain words', () {
      final now = DateTime.utc(2026, 10, 30, 10);
      expect(readableReason(afterFailure(op('a'), now, status: 'rejected', reason: 'données invalides', setAside: true)),
          'Refusé par le serveur : données invalides');
      expect(readableReason(afterFailure(op('b'), now, status: 'rejected', reason: 'refusé par le serveur', setAside: true)), 'Refusé par le serveur');
      expect(readableReason(afterFailure(op('c'), now, status: 'retry', reason: 'erreur du serveur (500)')), 'erreur du serveur (500)');
      expect(readableReason(op('d')), isNull);
    });
  });

  group('Dessin', () {
    MapFeature zone(String id, double lat, {String by = 'T1'}) => MapFeature(id: id, eventId: 'e', kind: FeatureKind.zone,
        points: [LatLng(lat, 2.0), LatLng(lat + 0.01, 2.0), LatLng(lat + 0.01, 2.01)], color: 0xFFE53935, strokeWidth: 4,
        createdBy: by, updatedBy: by, updatedAt: DateTime.utc(2026));

    test('handles: 8 px vertex, 12 px move cross, 44 px touch, middle of the sides', () {
      expect(vertexHandlePx, 8);
      expect(moveHandlePx, 12);
      expect(handleTouchPx, 44);
      final m = sideMiddles(zone('z', 48.0));
      expect(m.length, 3);
      expect(m.first.$1, 1);
      expect(m.first.$2.latitude, closeTo(48.005, 1e-9));
    });

    test('a vertex added in the middle of a side, one undo step', () {
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [zone('z', 48.0)]);
      c.select('z');
      c.beginEdit();
      c.insertVertex(1, const LatLng(48.005, 1.99));
      c.endEdit();
      expect(c.selected!.points.length, 4);
      c.undo();
      expect(c.feature('z')!.points.length, 3);
    });

    test('multiple selection: rectangle, toggle, own objects only, group of the logbook', () {
      final groups = <Map<String, dynamic>?>[];
      late DrawingController c;
      c = DrawingController(eventId: 'e', actorId: 'T1', initial: [zone('a', 48.0), zone('b', 48.1), zone('x', 48.2, by: 'T2')],
          onDeleted: (_) => groups.add(c.groupJson));
      c.canSelect = (f) => canMultiSelect(f, 'T1', pco: false);
      final r = selectionRect(project(const LatLng(48.25, 1.99)), project(const LatLng(47.99, 2.02)));
      c.addToSelection(featuresInRect(c.features, r, project).map((f) => f.id));
      expect(c.selection.map((f) => f.id).toSet(), {'a', 'b'});
      expect(c.isMulti, isTrue);
      expect(c.selected, isNull);
      c.toggle('b');
      expect(c.selection.map((f) => f.id), ['a']);
      c.toggle('b');
      c.deleteSelected();
      expect(c.features.map((f) => f.id), ['x']);
      expect(groups.length, 2);
      expect(groups.first!['n'], 2);
      expect(groups.first!['action'], 'delete');
      expect(groups.first!['id'], groups.last!['id']);
      // Undo brings both back at once.
      c.undo();
      expect(c.features.length, 3);
      expect(c.groupJson, isNull);
    });

    test('the PCO can select every object', () {
      expect(canMultiSelect(zone('x', 48.0, by: 'T2'), 'PCO', pco: true), isTrue);
      expect(canMultiSelect(zone('x', 48.0, by: 'T2'), 'T1', pco: false), isFalse);
    });

    test('moving together and colour of all, one undo step each', () {
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [zone('a', 48.0), zone('b', 48.1)]);
      c.addToSelection(['a', 'b']);
      c.beginEdit();
      c.moveSelected(0.5, 0);
      c.endEdit();
      expect(c.feature('a')!.points.first.latitude, closeTo(48.5, 1e-9));
      expect(c.feature('b')!.points.first.latitude, closeTo(48.6, 1e-9));
      c.setColor(0xFF1E88E5);
      expect(c.selection.every((f) => f.color == 0xFF1E88E5), isTrue);
      c.undo();
      c.undo();
      expect(c.feature('b')!.points.first.latitude, closeTo(48.1, 1e-9));
    });

    test('rectangle touching nothing selects nothing', () {
      expect(featuresInRect([zone('a', 48.0)], const Rect.fromLTWH(0, 0, 10, 10), project), isEmpty);
    });

    test('Texte: font size kept with the object and synchronised', () {
      final t = MapFeature(id: 't', eventId: 'e', kind: FeatureKind.text, points: const [LatLng(48, 2)], color: 0xFF000000,
          strokeWidth: 4, label: 'PC', updatedAt: DateTime.utc(2026));
      expect(t.toJson().containsKey('font_size'), isFalse);
      final c = DrawingController(eventId: 'e', actorId: 'T1', initial: [t]);
      c.select('t');
      c.setFontSize(28);
      expect(c.selected!.fontSize, 28);
      final j = c.selected!.toJson();
      expect(j['font_size'], 28);
      expect(MapFeature.fromJson(j).fontSize, 28);
      expect(textMarkerWidth(40) > textMarkerWidth(15), isTrue);
    });
  });
}
