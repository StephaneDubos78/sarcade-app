import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/export_formats.dart';
import 'package:sarcade_app/src/features/map/drawing/import_formats.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30, 18);
  MapFeature f(FeatureKind k, List<LatLng> pts, {String label = '', double? r}) =>
      MapFeature(id: '${k.name}-1', eventId: 'e', kind: k, points: pts, radiusM: r, color: 0xFFD93025, strokeWidth: 3, label: label, updatedAt: now);
  final objects = [
    f(FeatureKind.point, const [LatLng(48.8, 2.1)], label: 'PC <avancé>'),
    f(FeatureKind.line, const [LatLng(48.8, 2.1), LatLng(48.81, 2.12)], label: 'Axe'),
    f(FeatureKind.zone, const [LatLng(48.8, 2.1), LatLng(48.81, 2.1), LatLng(48.81, 2.11)], label: 'Secteur A'),
    f(FeatureKind.circle, const [LatLng(48.8, 2.1)], r: 500),
  ];

  test('export as KML and GPX, read back by the import', () {
    final kml = parseMapFile('x.kml', exportFeatures(objects, ExportFormat.kml));
    expect(kml.shapes.length, 4);
    expect(featuresToKml(objects), contains('PC &lt;avancé&gt;'));
    expect(featuresToKml(objects), contains('ff2530d9'));
    final gpx = parseMapFile('x.gpx', exportFeatures(objects, ExportFormat.gpx));
    expect(gpx.shapes.length, 4);
    final geo = parseMapFile('x.geojson', exportFeatures(objects, ExportFormat.geojson));
    expect(geo.shapes.length, 4);
  });

  test('a circle becomes a 36-point outline in KML and GPX', () {
    final pts = circleOutline(const LatLng(48.8, 2.1), 500);
    expect(pts.length, 36);
    expect(const Distance().as(LengthUnit.Meter, const LatLng(48.8, 2.1), pts[9]), closeTo(500, 2));
    expect(ExportFormat.gpx.extension, 'gpx');
    expect(ExportFormat.kml.mimeType, 'application/vnd.google-earth.kml+xml');
  });
}
