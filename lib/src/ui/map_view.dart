/// Small rules of the map screen V2, kept apart to be tested.
library;

import 'dart:math' as math;

/// Scale bar (OsmAnd): the longest « round » distance (1, 2, 5 × 10^n m)
/// fitting in [maxPx] at this zoom and latitude, with its width in pixels.
({double meters,double px,String label}) scaleBar(double zoom,double lat,{double maxPx=110}){
  final mPerPx=156543.03392*math.cos(lat*math.pi/180)/math.pow(2,zoom);
  final maxM=mPerPx*maxPx;
  var step=math.pow(10,(math.log(maxM)/math.ln10).floor()).toDouble();
  for(final f in const [5,2,1]){if(step*f<=maxM){step*=f;break;}}
  final label=step>=1000?'${(step/1000).toStringAsFixed(step%1000==0?0:1)} km':'${step.toStringAsFixed(0)} m';
  return (meters:step,px:step/mPerPx,label:label);
}

/// Last map view of an event (« reprendre là où on en était », Plex):
/// « lat,lon,zoom » kept on the device.
String encodeView(double lat,double lon,double zoom)=>'${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)},${zoom.toStringAsFixed(2)}';
({double lat,double lon,double zoom})? decodeView(String? v){
  final p=v?.split(',');
  if(p==null||p.length!=3)return null;
  final lat=double.tryParse(p[0]),lon=double.tryParse(p[1]),zoom=double.tryParse(p[2]);
  if(lat==null||lon==null||zoom==null||lat.abs()>90||lon.abs()>180||zoom<1||zoom>22)return null;
  return (lat:lat,lon:lon,zoom:zoom);
}

/// Links shown by the status pill: server, realtime, APRS of the server.
/// Null means not used (not counted).
({int ok,int total}) linksCount(List<bool?> links){
  final used=links.whereType<bool>().toList();
  return (ok:used.where((b)=>b).length,total:used.length);
}
