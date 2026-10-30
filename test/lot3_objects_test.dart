import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/map_objects.dart';
import 'package:sarcade_app/src/features/map/traces_layer.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';
import 'package:sarcade_app/src/features/poi/poi_icons.dart';
import 'package:sarcade_app/src/features/poi/poi_list.dart';
import 'package:sarcade_app/src/features/poi/poi_sheet.dart';
import 'package:sarcade_app/src/features/routes/route_models.dart';
import 'package:sarcade_app/src/features/routes/routes_layers.dart';
import 'package:sarcade_app/src/features/routes/waypoint_sheet.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/poi.dart';
import 'package:sarcade_app/src/models/position.dart';

/// Lot 3 « objets de la carte » (30 Oct 2026).
void main() {
  SarcadePoi poi(String id, String label, {String? by = 'TEL-02', String? icon, int hour = 18, double lat = 48.82}) =>
      SarcadePoi(id: id, eventId: 'e1', kind: 'designated', lat: lat, lon: 1.91,
          createdAt: DateTime.utc(2026, 10, 29, hour), label: label, createdBy: by, icon: icon);

  test('a new point: default name « Point HH:MM », icon kept', () {
    expect(defaultPoiName(DateTime(2026, 10, 30, 9, 5)), 'Point 09:05');
    expect(S.t('poi.defaultName', {'hm': '09:05'}), isNot(contains('désigné')));
    final j = newPoiJson(id: 'p', eventId: 'e1', at: const LatLng(48.8, 2.1), label: 'Gué', actor: 'TEL-02', drawColor: 0xFF43A047, icon: 'water');
    expect(SarcadePoi.fromJson(j).icon, 'water');
    expect(newPoiJson(id: 'p', eventId: 'e1', at: const LatLng(48.8, 2.1), actor: 'T', drawColor: 0, icon: 'pin').containsKey('icon'), isFalse);
    expect(poiIcons.length, greaterThanOrEqualTo(12));
    for (final k in poiIcons) {
      expect(poiIconLabel(k), isNot(startsWith('poi.icon.')));
    }
  });

  test('list of the points: search, filters, sort', () {
    final all = [poi('a', 'Parking nord', icon: 'parking', hour: 10, lat: 48.9), poi('b', 'Gué', by: 'TEL-03', hour: 12, lat: 48.81), poi('c', 'Ancien', by: null, hour: 8)];
    expect(filterPois(all).map((p) => p.id), ['b', 'a', 'c']);
    expect(filterPois(all, sort: PoiSort.name).map((p) => p.id), ['c', 'b', 'a']);
    expect(filterPois(all, sort: PoiSort.distance, from: const LatLng(48.8, 1.91)).first.id, 'b');
    expect(filterPois(all, query: 'park').map((p) => p.id), ['a']);
    expect(filterPois(all, icon: 'pin').map((p) => p.id), ['b', 'c']);
    expect(filterPois(all, author: 'TEL-03').map((p) => p.id), ['b']);
    expect(filterPois(all, author: '').map((p) => p.id), ['c']);
  });

  test('points that overlap on screen form one group', () {
    final all = [poi('a', 'A'), poi('b', 'B'), poi('c', 'C', lat: 49.5)];
    final groups = clusterPois(all, (l) => Offset(l.longitude * 1000, -l.latitude * 1000));
    expect(groups.map((g) => g.length).toList()..sort(), [1, 2]);
  });

  test('waypoints: label with the route, nearest point, rights', () {
    final r = RoutePlan({'id': 'r1', 'name': 'Ronde nord', 'created_by': 'TEL-01'});
    Waypoint wp(String id, double lat) => Waypoint({'id': id, 'route_id': 'r1', 'name': id, 'lat': lat, 'lon': 2.1});
    expect(waypointLabel(r, wp('P2', 48.8)), 'Ronde nord · P2');
    expect(nearestWaypoint([wp('P1', 48.80), wp('P2', 48.81)], const LatLng(48.809, 2.1))?.id, 'P2');
    expect(canEditWaypointOf(r, 'TEL-01'), isTrue);
    expect(canEditWaypointOf(r, 'PCO'), isTrue);
    expect(canEditWaypointOf(r, 'TEL-02'), isFalse);
    expect(waypointDotPx, 8);
    expect(waypointTouchPx, 44);
    expect(S.t('routes.new'), 'Nouvel itinéraire');
  });

  test('move orders: answered ones leave the map after 30 min, removal by PCO or author', () {
    final now = DateTime.utc(2026, 10, 30, 3);
    MoveOrder o(String status, int minAgo) => MoveOrder({'id': 'o', 'target_id': 'TEL-02', 'created_by': 'PCO', 'status': status,
        'updated_at': now.subtract(Duration(minutes: minAgo)).toIso8601String()});
    expect(moveOrderOnMap(o('arrived', 10), now), isTrue);
    expect(moveOrderOnMap(o('arrived', 31), now), isFalse);
    expect(moveOrderOnMap(o('refused', 45), now), isFalse);
    expect(moveOrderOnMap(o('accepted', 300), now), isTrue);
    expect(moveOrderOnMap(o('cancelled', 1), now), isFalse);
    expect(canRemoveMoveOrder(o('arrived', 1), 'PCO', pco: true), isTrue);
    expect(canRemoveMoveOrder(o('arrived', 1), 'TEL-02', pco: false), isFalse);
  });

  test('traces: 2 h by default, paler with age, pinned and all', () {
    expect(traceWindowFrom(null), 120);
    expect(traceWindowFrom('360'), 360);
    expect(traceWindowFrom('7'), 120);
    expect(traceAlpha(Duration.zero, 120), 1);
    expect(traceAlpha(const Duration(hours: 2), 120), closeTo(0.2, 1e-9));
    final now = DateTime.utc(2026, 10, 30, 3);
    SarcadePosition pos(String dev, int minAgo, {String source = 'device'}) => SarcadePosition(id: '$dev$minAgo', eventId: 'e1', deviceId: dev,
        lat: 48.8, lon: 2.1, time: now.subtract(Duration(minutes: minAgo)), source: source);
    expect(traceSegmentsOf([pos('a', 1), pos('a', 2), pos('a', 30), pos('a', 31), pos('a', 200)], now, 120).map((s) => s.length), [2, 2]);
    expect(traceSegmentsOf([pos('a', 1), pos('a', 200), pos('a', 201)], now, 0).length, 1);
    final onMap = [pos('a', 1), pos('aprs:F4X', 1, source: 'aprs')];
    expect(tracedStations(onMap, pinned: {'z'}, all: false, aprs: false), ['z']);
    expect(tracedStations(onMap, pinned: {}, all: true, aprs: false), ['a']);
    expect(tracedStations(onMap, pinned: {}, all: true, aprs: true), ['a', 'aprs:F4X']);
  });
}
