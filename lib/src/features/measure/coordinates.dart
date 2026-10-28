/// Coordinate formats (note « Mesure de distance vers un point désigné »,
/// validated): decimal degrees (default), degrees and decimal minutes (SAR,
/// aeronautical), QTH locator (radio amateurs); since 10 Oct 2026 also
/// degrees-minutes-seconds, UTM and MGRS, in display and input. WGS 84.
/// Pure code.
library;

import 'package:latlong2/latlong.dart';
import 'utm.dart';

export 'utm.dart' show formatUtm, formatMgrs, parseUtm, parseMgrs, toUtm, fromUtm;

enum CoordFormat{dd,dm,qth,dms,utm,mgrs}

/// The three formats always shown on the card; the others behind « More formats ».
const baseFormats=[CoordFormat.dd,CoordFormat.dm,CoordFormat.qth];
const extraFormats=[CoordFormat.dms,CoordFormat.utm,CoordFormat.mgrs];

CoordFormat coordFormatFrom(String? v)=>CoordFormat.values.firstWhere((f)=>f.name==v,orElse:()=>CoordFormat.dd);

String _hemi(double v,String pos,String neg)=>v>=0?pos:neg;

/// « 48,80123 N · 2,13456 E » (French decimal comma by default).
String formatDd(LatLng p,{String decimal=','})=>
  '${p.latitude.abs().toStringAsFixed(5).replaceAll('.',decimal)} ${_hemi(p.latitude,'N','S')} · '
  '${p.longitude.abs().toStringAsFixed(5).replaceAll('.',decimal)} ${_hemi(p.longitude,'E','O')}';

/// « 48°48,074′ N · 002°08,074′ E ».
String formatDm(LatLng p,{String decimal=','}){
  String part(double v,int degWidth){
    final a=v.abs(); var d=a.floor(); var m=(a-d)*60;
    if(double.parse(m.toStringAsFixed(3))>=60){d+=1;m=0;}
    return '${d.toString().padLeft(degWidth,'0')}°${m.toStringAsFixed(3).padLeft(6,'0').replaceAll('.',decimal)}′';
  }
  return '${part(p.latitude,2)} ${_hemi(p.latitude,'N','S')} · ${part(p.longitude,3)} ${_hemi(p.longitude,'E','O')}';
}

/// « 48°48′04,4″ N · 002°08′04,4″ E » (tenth of a second, about 3 m).
String formatDms(LatLng p,{String decimal=','}){
  String part(double v,int degWidth){
    final a=v.abs(); var d=a.floor(); final mm=(a-d)*60; var m=mm.floor(); var sec=(mm-m)*60;
    if(double.parse(sec.toStringAsFixed(1))>=60){sec=0;m+=1;}
    if(m>=60){m=0;d+=1;}
    return '${d.toString().padLeft(degWidth,'0')}°${m.toString().padLeft(2,'0')}′'
      '${sec.toStringAsFixed(1).padLeft(4,'0').replaceAll('.',decimal)}″';
  }
  return '${part(p.latitude,2)} ${_hemi(p.latitude,'N','S')} · ${part(p.longitude,3)} ${_hemi(p.longitude,'E','O')}';
}

/// Maidenhead locator, 6 characters by default (8 or 10 on request).
String formatQth(LatLng p,{int length=6}){
  var lon=p.longitude+180, lat=p.latitude+90;
  lon=lon.clamp(0,359.999999); lat=lat.clamp(0,179.999999);
  final b=StringBuffer();
  const upper='ABCDEFGHIJKLMNOPQRSTUVWXYZ', lower='abcdefghijklmnopqrstuvwxyz';
  // Field (20° x 10°), square (2° x 1°), subsquare (5′ x 2.5′), then 10 x 10 and 24 x 24.
  var lonSize=20.0, latSize=10.0;
  b..write(upper[(lon/lonSize).floor()])..write(upper[(lat/latSize).floor()]);
  lon%=lonSize; lat%=latSize;
  var pairs=1;
  while(b.length<length){
    final digits=pairs.isOdd;
    final div=digits?10:24;
    lonSize/=div; latSize/=div;
    final x=(lon/lonSize).floor(), y=(lat/latSize).floor();
    if(digits){b..write(x)..write(y);}else{b..write(lower[x])..write(lower[y]);}
    lon%=lonSize; lat%=latSize;
    pairs++;
  }
  return b.toString().toUpperCase();
}

/// Centre of a locator square.
LatLng? parseQth(String text){
  final s=text.trim().toUpperCase();
  if(!RegExp(r'^[A-R]{2}([0-9]{2}([A-X]{2}([0-9]{2}([A-X]{2})?)?)?)?$').hasMatch(s))return null;
  var lon=-180.0, lat=-90.0, lonSize=20.0, latSize=10.0;
  lon+=(s.codeUnitAt(0)-65)*lonSize; lat+=(s.codeUnitAt(1)-65)*latSize;
  var i=2, pair=1;
  while(i<s.length){
    final digits=pair.isOdd;
    final div=digits?10:24;
    lonSize/=div; latSize/=div;
    final x=digits?int.parse(s[i]):s.codeUnitAt(i)-65;
    final y=digits?int.parse(s[i+1]):s.codeUnitAt(i+1)-65;
    lon+=x*lonSize; lat+=y*latSize;
    i+=2; pair++;
  }
  return LatLng(lat+latSize/2,lon+lonSize/2);
}

/// Coordinates typed by the operator, in any of the three formats:
/// « 48.80123, 2.13456 », « 48,80123 N 2,13456 E », « 48°48,074 N 2°08,074 E »,
/// « JN18bt ». Null when not understood.
LatLng? parseCoordinates(String text){
  final qth=parseQth(text);
  if(qth!=null)return qth;
  final grid=parseMgrs(text)??parseUtm(text);
  if(grid!=null)return grid;
  final t=text.trim().toUpperCase().replaceAll('′',"'").replaceAll('″','"').replaceAll("''",'"');
  // Degrees, minutes and seconds.
  final dms=RegExp(r"""(\d{1,3})\s*[°D ]\s*(\d{1,2})\s*['M ]\s*(\d{1,2}(?:[.,]\d+)?)\s*"?\s*([NS])[\s,;·]+(\d{1,3})\s*[°D ]\s*(\d{1,2})\s*['M ]\s*(\d{1,2}(?:[.,]\d+)?)\s*"?\s*([EWO])""").firstMatch(t);
  if(dms!=null){
    double v(String d,String m,String sec)=>int.parse(d)+int.parse(m)/60+double.parse(sec.replaceAll(',','.'))/3600;
    final lat=v(dms[1]!,dms[2]!,dms[3]!)*(dms[4]=='S'?-1:1), lon=v(dms[5]!,dms[6]!,dms[7]!)*((dms[8]=='W'||dms[8]=='O')?-1:1);
    return _valid(lat,lon);
  }
  // Degrees and minutes.
  final dm=RegExp(r"""(\d{1,3})\s*[°D ]\s*(\d{1,2}(?:[.,]\d+)?)\s*'?\s*([NS])[\s,;·]+(\d{1,3})\s*[°D ]\s*(\d{1,2}(?:[.,]\d+)?)\s*'?\s*([EWO])""").firstMatch(t);
  if(dm!=null){
    double v(String deg,String min)=>int.parse(deg)+double.parse(min.replaceAll(',','.'))/60;
    final lat=v(dm[1]!,dm[2]!)*(dm[3]=='S'?-1:1), lon=v(dm[4]!,dm[5]!)*((dm[6]=='W'||dm[6]=='O')?-1:1);
    return _valid(lat,lon);
  }
  // Decimal degrees with hemispheres.
  final h=RegExp(r'(\d{1,2}(?:[.,]\d+)?)\s*°?\s*([NS])[\s,;·]+(\d{1,3}(?:[.,]\d+)?)\s*°?\s*([EWO])').firstMatch(t);
  if(h!=null){
    final lat=double.parse(h[1]!.replaceAll(',','.'))*(h[2]=='S'?-1:1);
    final lon=double.parse(h[3]!.replaceAll(',','.'))*((h[4]=='W'||h[4]=='O')?-1:1);
    return _valid(lat,lon);
  }
  // Signed decimal degrees « lat, lon » (dot decimals) or « lat; lon » / « lat lon ».
  final s=RegExp(r'^\s*(-?\d{1,2}(?:\.\d+)?)\s*[,; ]\s*(-?\d{1,3}(?:\.\d+)?)\s*$').firstMatch(t)
    ??RegExp(r'^\s*(-?\d{1,2}(?:,\d+)?)\s*[; ]\s*(-?\d{1,3}(?:,\d+)?)\s*$').firstMatch(t);
  if(s!=null)return _valid(double.parse(s[1]!.replaceAll(',','.')),double.parse(s[2]!.replaceAll(',','.')));
  return null;
}

LatLng? _valid(double lat,double lon)=>(lat.abs()<=90&&lon.abs()<=180)?LatLng(lat,lon):null;

/// [mgrsDigits]: 4 (10 m, default) or 5 (1 m). UTM and MGRS give « — »
/// in the polar areas.
String formatCoordinates(LatLng p,CoordFormat f,{int mgrsDigits=4})=>switch(f){
  CoordFormat.dd=>formatDd(p),
  CoordFormat.dm=>formatDm(p),
  CoordFormat.qth=>formatQth(p),
  CoordFormat.dms=>formatDms(p),
  CoordFormat.utm=>formatUtm(p)??'—',
  CoordFormat.mgrs=>formatMgrs(p,digits:mgrsDigits)??'—',
};

/// Formats shown on the card: the main format first, then the base ones;
/// the remaining formats behind « More formats ».
({List<CoordFormat> shown,List<CoordFormat> more}) cardFormats(CoordFormat main){
  final shown=[main,...baseFormats.where((f)=>f!=main)];
  return (shown:shown,more:[for(final f in CoordFormat.values) if(!shown.contains(f)) f]);
}
