/// Lambert 93 and DFCI grid (lot 5, « Convertisseur de coordonnées
/// étoffé », 30 Oct 2026). Pure code, without network.
///
/// * Lambert 93 (EPSG:2154): conformal conic projection on RGF93 / GRS80,
///   standard parallels 44° and 49°, origin 46°30′ N 3° E, false origin
///   700 000 / 6 600 000 m. RGF93 is taken equal to WGS 84 (sub-metre).
/// * DFCI (forest fire grid of the IGN): squares of 100 km, 20 km, 2 km
///   and quarters, laid on Lambert II étendu (EPSG:27572, NTF, Clarke 1880
///   IGN, Paris meridian). NTF ↔ WGS 84 by the three-parameter shift of the
///   IGN (-168, -60, +320 m) instead of the NTF grid: about ±2 m in
///   metropolitan France, far below the 500 m quarter of the DFCI grid.
///   Lettering as ol-ext (J.-M. Viglino, IGN), letters I and J skipped.
library;

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

double _rad(double d)=>d*math.pi/180;
double _deg(double r)=>r*180/math.pi;

class _Lcc {
  final double a, e, n, c, xs, ys, lon0;
  const _Lcc(this.a,this.e,this.n,this.c,this.xs,this.ys,this.lon0);

  static double _t(double lat,double e)=>math.tan(math.pi/4-lat/2)/math.pow((1-e*math.sin(lat))/(1+e*math.sin(lat)),e/2);
  static double _m(double lat,double e)=>math.cos(lat)/math.sqrt(1-e*e*math.sin(lat)*math.sin(lat));

  /// Secant cone (two standard parallels).
  factory _Lcc.secant(double a,double e,double lat0,double lat1,double lat2,double lon0,double x0,double y0){
    final n=(math.log(_m(lat1,e))-math.log(_m(lat2,e)))/(math.log(_t(lat1,e))-math.log(_t(lat2,e)));
    final f=a*_m(lat1,e)/(n*math.pow(_t(lat1,e),n));
    return _Lcc(a,e,n,f,x0,y0+f*math.pow(_t(lat0,e),n).toDouble(),lon0);
  }
  /// Tangent cone with a scale factor.
  factory _Lcc.tangent(double a,double e,double lat0,double k0,double lon0,double x0,double y0){
    final n=math.sin(lat0);
    final f=a*k0*_m(lat0,e)/(n*math.pow(_t(lat0,e),n));
    return _Lcc(a,e,n,f,x0,y0+f*math.pow(_t(lat0,e),n).toDouble(),lon0);
  }

  (double,double) forward(double lat,double lon){
    final r=c*math.pow(_t(lat,e),n).toDouble(), th=n*(lon-lon0);
    return (xs+r*math.sin(th),ys-r*math.cos(th));
  }

  (double,double) inverse(double x,double y){
    final dx=x-xs, dy=ys-y;
    final r=math.sqrt(dx*dx+dy*dy)*(n<0?-1:1);
    final t=math.pow(r/c,1/n).toDouble();
    final lon=lon0+math.atan2(dx,dy)/n;
    var lat=math.pi/2-2*math.atan(t);
    for(var i=0;i<12;i++){
      final es=e*math.sin(lat);
      lat=math.pi/2-2*math.atan(t*math.pow((1-es)/(1+es),e/2));
    }
    return (lat,lon);
  }
}

// GRS80
final _grsE=math.sqrt((1/298.257222101)*(2-1/298.257222101));
final _l93=_Lcc.secant(6378137.0,_grsE,_rad(46.5),_rad(44),_rad(49),_rad(3),700000,6600000);
// Clarke 1880 IGN, Lambert II étendu (meridian of Paris).
const _clA=6378249.2, _clB=6356515.0;
final _clE2=1-(_clB/_clA)*(_clB/_clA);
final _l2e=_Lcc.tangent(_clA,math.sqrt(_clE2),_rad(46.8),0.99987742,_rad(2+20/60+14.025/3600),600000,2200000);
const _wA=6378137.0, _wF=1/298.257223563;
const _wE2=_wF*(2-_wF);
/// NTF → WGS 84 shift of the IGN (metres).
const _shift=(-168.0,-60.0,320.0);

(double,double,double) _toXyz(double lat,double lon,double a,double e2){
  final s=math.sin(lat), nn=a/math.sqrt(1-e2*s*s);
  return (nn*math.cos(lat)*math.cos(lon),nn*math.cos(lat)*math.sin(lon),nn*(1-e2)*s);
}
(double,double) _fromXyz(double x,double y,double z,double a,double e2){
  final lon=math.atan2(y,x), p=math.sqrt(x*x+y*y);
  var lat=math.atan2(z,p*(1-e2));
  for(var i=0;i<10;i++){final s=math.sin(lat);final nn=a/math.sqrt(1-e2*s*s);lat=math.atan2(z+e2*nn*s,p);}
  return (lat,lon);
}

/// WGS 84 → Lambert 93, metres (x east, y north).
({double x,double y}) toLambert93(LatLng p){
  final (x,y)=_l93.forward(_rad(p.latitude),_rad(p.longitude));
  return (x:x,y:y);
}
LatLng fromLambert93(double x,double y){
  final (lat,lon)=_l93.inverse(x,y);
  return LatLng(_deg(lat),_deg(lon));
}

/// WGS 84 → Lambert II étendu (NTF), metres.
({double x,double y}) toLambert2e(LatLng p){
  final (x,y,z)=_toXyz(_rad(p.latitude),_rad(p.longitude),_wA,_wE2);
  // WGS 84 = NTF + shift, so NTF = WGS 84 - shift.
  final (lat,lon)=_fromXyz(x-_shift.$1,y-_shift.$2,z-_shift.$3,_clA,_clE2);
  final (e,n)=_l2e.forward(lat,lon);
  return (x:e,y:n);
}
LatLng fromLambert2e(double e,double n){
  final (lat,lon)=_l2e.inverse(e,n);
  final (x,y,z)=_toXyz(lat,lon,_clA,_clE2);
  final (la,lo)=_fromXyz(x+_shift.$1,y+_shift.$2,z+_shift.$3,_wA,_wE2);
  return LatLng(_deg(la),_deg(lo));
}

String _group(int v){
  final s=v.abs().toString(), b=StringBuffer();
  for(var i=0;i<s.length;i++){if(i>0&&(s.length-i)%3==0)b.write(' ');b.write(s[i]);}
  return (v<0?'-':'')+b.toString();
}

/// « X 636 433 · Y 6 856 031 » (metre, Lambert 93); null far from France.
String? formatLambert93(LatLng p){
  if(!inLambert93Area(p))return null;
  final l=toLambert93(p);
  return 'X ${_group(l.x.floor())} · Y ${_group(l.y.floor())}';
}

/// Metropolitan France and its surroundings (the projection is defined
/// there; elsewhere the numbers mean nothing).
bool inLambert93Area(LatLng p)=>p.latitude>=40&&p.latitude<=52&&p.longitude>=-7&&p.longitude<=11.5;

/// « X 636433 Y 6856031 », « 636433 6856031 », « L93 636 433 / 6 856 031 ».
LatLng? parseLambert93(String text){
  final t=text.toUpperCase().replaceFirst(RegExp(r'^\s*L(?:AMBERT)?\s*93\s*:?'),'')
    .replaceAll(RegExp(r'(?<=\d)[ \u202F\u00A0](?=\d{3}\b)'),'');
  final m=RegExp(r'^\s*(?:X\s*[:=]?\s*)?(\d{5,7}(?:[.,]\d+)?)\s*(?:M\b)?\s*[,;/·\s]\s*(?:Y\s*[:=]?\s*)?(\d{7}(?:[.,]\d+)?)\s*(?:M\b)?\s*(?:\(?L93\)?)?\s*$').firstMatch(t);
  if(m==null)return null;
  final x=double.parse(m[1]!.replaceAll(',','.')), y=double.parse(m[2]!.replaceAll(',','.'));
  if(x<0||x>1300000||y<6000000||y>7200000)return null;
  return fromLambert93(x,y);
}

/// DFCI index « FL82C1.5 » (level 3, about 1 km); null outside the grid.
String? formatDfci(LatLng p,{int level=3}){
  if(!inLambert93Area(p))return null;
  final l=toLambert2e(p); final x=l.x, y=l.y;
  if(x<0||x>1200000||y<1600000||y>2700000)return null;
  const step=100000.0, step1=20000.0, step2=2000.0;
  final b=StringBuffer()
    ..writeCharCode(65+((x<800000?x:x+200000)/step).floor())
    ..writeCharCode(65+((y<2300000?y:y+200000)/step).floor()-15);
  if(level==0)return b.toString();
  b..write(2*((x%step)/step1).floor())..write(2*((y%step)/step1).floor());
  if(level==1)return b.toString();
  final x0=((x%step1)/step2).floor();
  b..writeCharCode(65+(x0<8?x0:x0+2))..write(((y%step1)/step2).floor());
  if(level==2)return b.toString();
  final x3=((x%step2)/500).floor(), y3=((y%step2)/500).floor();
  final q=x3<1?(y3>1?1:4):x3>2?(y3>1?2:3):y3>2?(x3<2?1:2):y3<1?(x3<2?4:3):5;
  return '$b.$q';
}

/// Centre of a DFCI square (« FL82C1 », « FL82C1.5 », « FL 82 C 1 . 5 »).
LatLng? parseDfci(String text){
  final s=text.toUpperCase().replaceAll(RegExp(r'\s'),'');
  final m=RegExp(r'^([A-HK-N])([B-HK-N])(?:([02468])([02468])(?:([A-HK-L])(\d)(?:\.([1-5]))?)?)?$').firstMatch(s);
  if(m==null)return null;
  int ix(String c){final v=c.codeUnitAt(0)-65;return v<8?v:v-2;}
  var step=100000.0;
  var x=ix(m[1]!)*step, y=ix(m[2]!)*step+1500000;
  ({double x,double y}) c;
  if(m[3]==null){c=(x:x+step/2,y:y+step/2);}
  else{
    step/=5; x+=int.parse(m[3]!)/2*step; y+=int.parse(m[4]!)/2*step;
    if(m[5]==null){c=(x:x+step/2,y:y+step/2);}
    else{
      step/=10; x+=ix(m[5]!)*step; y+=int.parse(m[6]!)*step;
      c=switch(m[7]){'1'=>(x:x+step/4,y:y+3*step/4),'2'=>(x:x+3*step/4,y:y+3*step/4),
        '3'=>(x:x+3*step/4,y:y+step/4),'4'=>(x:x+step/4,y:y+step/4),_=>(x:x+step/2,y:y+step/2)};
    }
  }
  return fromLambert2e(c.x,c.y);
}
