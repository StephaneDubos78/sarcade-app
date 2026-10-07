import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Mean Earth radius in metres (IUGG), consistent for distances and areas.
const earthRadiusM=6371008.8;

double _rad(double d)=>d*math.pi/180;
double _deg(double r)=>r*180/math.pi;

/// Great-circle distance in metres (haversine).
double distanceM(LatLng a,LatLng b){
  final dLat=_rad(b.latitude-a.latitude), dLon=_rad(b.longitude-a.longitude);
  final h=math.pow(math.sin(dLat/2),2)+math.cos(_rad(a.latitude))*math.cos(_rad(b.latitude))*math.pow(math.sin(dLon/2),2);
  return 2*earthRadiusM*math.asin(math.min(1,math.sqrt(h.toDouble())));
}

double pathLength(List<LatLng> points){
  var total=0.0;
  for(var i=1;i<points.length;i++){total+=distanceM(points[i-1],points[i]);}
  return total;
}

/// Initial bearing from [a] to [b], degrees clockwise from north in [0, 360).
double bearingDeg(LatLng a,LatLng b){
  final p1=_rad(a.latitude), p2=_rad(b.latitude), dl=_rad(b.longitude-a.longitude);
  final y=math.sin(dl)*math.cos(p2);
  final x=math.cos(p1)*math.sin(p2)-math.sin(p1)*math.cos(p2)*math.cos(dl);
  return (_deg(math.atan2(y,x))+360)%360;
}

/// Point reached from [origin] after [distance] metres on [bearing] degrees.
LatLng destination(LatLng origin,double distance,double bearing){
  final d=distance/earthRadiusM, b=_rad(bearing), p1=_rad(origin.latitude), l1=_rad(origin.longitude);
  final p2=math.asin(math.sin(p1)*math.cos(d)+math.cos(p1)*math.sin(d)*math.cos(b));
  final l2=l1+math.atan2(math.sin(b)*math.sin(d)*math.cos(p1),math.cos(d)-math.sin(p1)*math.sin(p2));
  return LatLng(_deg(p2),((_deg(l2)+540)%360)-180);
}

/// Area of a simple polygon on the sphere, in square metres.
/// Spherical excess formula, accurate for search sectors of any practical size.
double polygonArea(List<LatLng> ring){
  if(ring.length<3)return 0;
  var sum=0.0;
  for(var i=0;i<ring.length;i++){
    final a=ring[i], b=ring[(i+1)%ring.length];
    sum+=_rad(b.longitude-a.longitude)*(2+math.sin(_rad(a.latitude))+math.sin(_rad(b.latitude)));
  }
  return (sum*earthRadiusM*earthRadiusM/2).abs();
}

double circleArea(double radiusM)=>math.pi*radiusM*radiusM;

/// Four corners of the lat/lon-aligned rectangle spanned by two opposite corners.
List<LatLng> rectangleCorners(LatLng a,LatLng b)=>[
  LatLng(a.latitude,a.longitude),LatLng(a.latitude,b.longitude),
  LatLng(b.latitude,b.longitude),LatLng(b.latitude,a.longitude),
];

LatLng centroid(List<LatLng> points){
  if(points.isEmpty)return const LatLng(0,0);
  var lat=0.0, lon=0.0;
  for(final p in points){lat+=p.latitude;lon+=p.longitude;}
  return LatLng(lat/points.length,lon/points.length);
}

String _fr(double v,int digits)=>v.toStringAsFixed(digits).replaceAll('.',',');

/// French display of a distance: "850 m", "1,25 km", "12,4 km".
String formatDistance(double m){
  if(m<1000)return '${m.round()} m';
  if(m<10000)return '${_fr(m/1000,2)} km';
  return '${_fr(m/1000,1)} km';
}

/// French display of an area: "850 m²", "2,4 ha", "3,10 km²".
String formatArea(double m2){
  if(m2<10000)return '${m2.round()} m²';
  if(m2<1000000)return '${_fr(m2/10000,m2<100000?2:1)} ha';
  return '${_fr(m2/1000000,2)} km²';
}
