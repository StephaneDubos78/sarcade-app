import 'package:latlong2/latlong.dart';

/// View of the map of this device, copied onto a TV by « Envoyer ma vue »
/// (29 October 2026): centre, zoom and base map.
typedef TvView=({LatLng center,double zoom,String basemapId,String? tileUrl,String attribution});

/// Set by the map page while it is open; null elsewhere.
TvView? Function()? currentMapView;

Map<String,dynamic> tvViewJson(TvView v)=>{
  'lat':v.center.latitude,'lon':v.center.longitude,'zoom':double.parse(v.zoom.toStringAsFixed(2)),
  'basemap':v.basemapId,
  // Only an online https base map can be shown by the TV.
  if(v.tileUrl!=null&&v.tileUrl!.startsWith('https://'))'tile_url':v.tileUrl,
  'attribution':v.attribution,
};
