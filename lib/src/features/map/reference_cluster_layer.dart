import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/reference_site.dart';

/// Radio reference sites (high points, relays) grouped on screen when the
/// map is zoomed out, so that the 183 sites of the ADRASEC78 map do not hide
/// the drawn objects and their labels (test of 23 Oct 2026).
///
/// Sites closer than [cellPx] on screen form a numbered circle; tapping it
/// zooms in on the group. From [clusterUntilZoom] every site is shown alone.
class ReferenceClusterLayer extends StatelessWidget {
  const ReferenceClusterLayer({super.key, required this.sites, required this.onSelect,
      this.cellPx = 56, this.clusterUntilZoom = 13});

  final List<ReferenceSite> sites;
  final void Function(ReferenceSite) onSelect;
  final double cellPx;
  final double clusterUntilZoom;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final markers = <Marker>[];
    if (camera.zoom >= clusterUntilZoom) {
      markers.addAll(sites.map((s) => _siteMarker(s)));
    } else {
      final cells = <(int, int), List<ReferenceSite>>{};
      for (final s in sites) {
        final p = camera.projectAtZoom(LatLng(s.lat, s.lon));
        final key = ((p.dx / cellPx).floor(), (p.dy / cellPx).floor());
        (cells[key] ??= []).add(s);
      }
      for (final group in cells.values) {
        markers.add(group.length == 1 ? _siteMarker(group.first) : _clusterMarker(context, camera, group));
      }
    }
    return MarkerLayer(markers: markers);
  }

  Marker _siteMarker(ReferenceSite s) => Marker(
        point: LatLng(s.lat, s.lon),
        width: 30,
        height: 30,
        child: Tooltip(
          message: s.callsign?.isNotEmpty == true ? '${s.name} · ${s.callsign}' : s.name,
          child: GestureDetector(
            onTap: () => onSelect(s),
            child: Icon(s.isHighPoint ? Icons.terrain : Icons.cell_tower, size: 24,
                color: s.isHighPoint ? Colors.indigo : Colors.deepOrange),
          ),
        ),
      );

  Marker _clusterMarker(BuildContext context, MapCamera camera, List<ReferenceSite> group) {
    final lat = group.map((s) => s.lat).reduce((a, b) => a + b) / group.length;
    final lon = group.map((s) => s.lon).reduce((a, b) => a + b) / group.length;
    final relays = group.where((s) => s.isRelay).length;
    final highPoints = group.length - relays;
    // Indigo for high points only, orange for relays only, mixed otherwise.
    final color = relays == 0 ? Colors.indigo : highPoints == 0 ? Colors.deepOrange : Colors.purple;
    final size = 30.0 + math.min(16.0, group.length.toDouble());
    return Marker(
      point: LatLng(lat, lon),
      width: size,
      height: size,
      child: Tooltip(
        message: [if (highPoints > 0) '$highPoints points hauts', if (relays > 0) '$relays relais'].join(' · '),
        child: GestureDetector(
          onTap: () => MapController.of(context).move(LatLng(lat, lon), math.min(camera.zoom + 2, clusterUntilZoom)),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 2)],
            ),
            child: Text('${group.length}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
      ),
    );
  }
}
