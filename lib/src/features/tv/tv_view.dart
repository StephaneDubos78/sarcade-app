import 'package:latlong2/latlong.dart';

/// View of the map of this device, copied onto a TV by « Envoyer ma vue »
/// (29 October 2026): centre, zoom and base map.
typedef TvView=({LatLng center,double zoom,String basemapId,String? tileUrl,String attribution});

/// Set by the map page while it is open; null elsewhere.
TvView? Function()? currentMapView;

/// Step 2 (decision of 29 Oct 2026, 12 h 12): settings applied by the TV,
/// not a screenshot — layers shown, opacity per layer, Messages panel.
typedef TvOptions=({Map<String,bool> layers,Map<String,double> opacity,bool messages});
TvOptions? Function()? currentMapOptions;

Map<String,dynamic> tvViewJson(TvView v,{TvOptions? options})=>{
  if(options!=null)...{
    'layers':options.layers,
    'opacity':{for(final e in options.opacity.entries)e.key:double.parse(e.value.clamp(0.1,1.0).toStringAsFixed(2))},
    'messages':options.messages,
  },
  'lat':v.center.latitude,'lon':v.center.longitude,'zoom':double.parse(v.zoom.toStringAsFixed(2)),
  'basemap':v.basemapId,
  // Only an online https base map can be shown by the TV.
  if(v.tileUrl!=null&&v.tileUrl!.startsWith('https://'))'tile_url':v.tileUrl,
  'attribution':v.attribution,
};
