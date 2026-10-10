/// UTM and MGRS coordinates on WGS 84 (note « Mesure de distance vers un
/// point désigné », formats added on 10 Oct 2026). Pure code, without
/// network. Transverse Mercator series of Snyder (USGS Professional Paper
/// 1395), millimetric in the zone; MGRS with the « AA » lettering of
/// WGS 84 and the exceptions of Norway and Svalbard. Outside 80° S – 84° N
/// (polar UPS grid) there is no UTM coordinate: null.
library;

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

const _a=6378137.0, _f=1/298.257223563, _k0=0.9996;
const _e2=_f*(2-_f);
const _ep2=_e2/(1-_e2);
const _bands='CDEFGHJKLMNPQRSTUVWX';

class Utm {
  final int zone; final String band; final double easting, northing;
  const Utm(this.zone,this.band,this.easting,this.northing);
  bool get north=>band.compareTo('N')>=0;
  @override String toString()=>'$zone$band ${easting.floor()} ${northing.floor()}';
}

double _rad(double d)=>d*math.pi/180;
double _deg(double r)=>r*180/math.pi;

int utmZone(double lat,double lon){
  var lo=lon; if(lo>=180)lo-=360;
  var zone=((lo+180)/6).floor()+1;
  if(zone>60)zone=60;
  if(lat>=56&&lat<64&&lo>=3&&lo<12)return 32;
  if(lat>=72&&lat<=84&&lo>=0){
    if(lo<9)return 31;
    if(lo<21)return 33;
    if(lo<33)return 35;
    if(lo<42)return 37;
  }
  return zone;
}

String? latitudeBand(double lat){
  if(lat< -80||lat>84)return null;
  final i=((lat+80)/8).floor();
  return _bands[i.clamp(0,19)];
}

double _meridianArc(double phi){
  const e4=_e2*_e2, e6=e4*_e2;
  return _a*((1-_e2/4-3*e4/64-5*e6/256)*phi-(3*_e2/8+3*e4/32+45*e6/1024)*math.sin(2*phi)
    +(15*e4/256+45*e6/1024)*math.sin(4*phi)-(35*e6/3072)*math.sin(6*phi));
}

/// UTM coordinate of a point, null outside 80° S – 84° N.
Utm? toUtm(LatLng p,{int? forceZone}){
  final band=latitudeBand(p.latitude);
  if(band==null)return null;
  final zone=forceZone??utmZone(p.latitude,p.longitude);
  final lon0=_rad((zone-1)*6-180+3.0);
  final phi=_rad(p.latitude), lam=_rad(p.longitude);
  final sinPhi=math.sin(phi), cosPhi=math.cos(phi), tanPhi=math.tan(phi);
  final n=_a/math.sqrt(1-_e2*sinPhi*sinPhi);
  final t=tanPhi*tanPhi, c=_ep2*cosPhi*cosPhi;
  var dl=lam-lon0;
  if(dl>math.pi)dl-=2*math.pi;
  if(dl< -math.pi)dl+=2*math.pi;
  final aa=cosPhi*dl;
  final m=_meridianArc(phi);
  final x=_k0*n*(aa+(1-t+c)*math.pow(aa,3)/6+(5-18*t+t*t+72*c-58*_ep2)*math.pow(aa,5)/120)+500000;
  var y=_k0*(m+n*tanPhi*(aa*aa/2+(5-t+9*c+4*c*c)*math.pow(aa,4)/24+(61-58*t+t*t+600*c-330*_ep2)*math.pow(aa,6)/720));
  if(p.latitude<0)y+=10000000;
  return Utm(zone,band,x,y);
}

/// Point of a UTM coordinate (hemisphere given by the band letter).
LatLng? fromUtm(int zone,bool north,double easting,double northing){
  if(zone<1||zone>60)return null;
  final lon0=_rad((zone-1)*6-180+3.0);
  final x=easting-500000, y=north?northing:northing-10000000;
  const e4=_e2*_e2, e6=e4*_e2;
  final m=y/_k0;
  final mu=m/(_a*(1-_e2/4-3*e4/64-5*e6/256));
  final e1=(1-math.sqrt(1-_e2))/(1+math.sqrt(1-_e2));
  final phi1=mu+(3*e1/2-27*math.pow(e1,3)/32)*math.sin(2*mu)+(21*e1*e1/16-55*math.pow(e1,4)/32)*math.sin(4*mu)
    +(151*math.pow(e1,3)/96)*math.sin(6*mu)+(1097*math.pow(e1,4)/512)*math.sin(8*mu);
  final s1=math.sin(phi1), c1=math.cos(phi1), t1=math.tan(phi1)*math.tan(phi1);
  final cc1=_ep2*c1*c1;
  final n1=_a/math.sqrt(1-_e2*s1*s1);
  final r1=_a*(1-_e2)/math.pow(1-_e2*s1*s1,1.5);
  final d=x/(n1*_k0);
  final phi=phi1-(n1*math.tan(phi1)/r1)*(d*d/2-(5+3*t1+10*cc1-4*cc1*cc1-9*_ep2)*math.pow(d,4)/24
    +(61+90*t1+298*cc1+45*t1*t1-252*_ep2-3*cc1*cc1)*math.pow(d,6)/720);
  final lam=lon0+(d-(1+2*t1+cc1)*math.pow(d,3)/6+(5-2*cc1+28*t1-3*cc1*cc1+8*_ep2+24*t1*t1)*math.pow(d,5)/120)/c1;
  final lat=_deg(phi), lon=(_deg(lam)+540)%360-180;
  if(lat.abs()>90)return null;
  return LatLng(lat,lon);
}

/// « 31U 431234 5401234 » (metres, truncated).
String? formatUtm(LatLng p){
  final u=toUtm(p);
  return u==null?null:'${u.zone}${u.band} ${u.easting.floor()} ${u.northing.floor()}';
}

/// « 31U 431234 5401234 », « 31 U 431234E 5401234N ».
LatLng? parseUtm(String text){
  final m=RegExp(r'^\s*(\d{1,2})\s*([C-HJ-NP-X])\s+(\d{6}(?:[.,]\d+)?)\s*[mE]?\s*[,; ]?\s*(\d{6,7}(?:[.,]\d+)?)\s*[mN]?\s*$')
    .firstMatch(text.toUpperCase());
  if(m==null)return null;
  final zone=int.parse(m[1]!), band=m[2]!;
  final e=double.parse(m[3]!.replaceAll(',','.')), n=double.parse(m[4]!.replaceAll(',','.'));
  final p=fromUtm(zone,band.compareTo('N')>=0,e,n);
  // The band must match the computed latitude (typing errors), with a
  // tolerance at the limits of the band.
  if(p==null)return null;
  final bottom=_bandBottom(band), top=bottom+(band=='X'?12:8);
  return p.latitude>=bottom-0.5&&p.latitude<=top+0.5?p:null;
}

const _colSets=['ABCDEFGH','JKLMNPQR','STUVWXYZ'];
const _rows='ABCDEFGHJKLMNPQRSTUV';

double _bandBottom(String band)=>-80.0+_bands.indexOf(band)*8;

/// MGRS reference, [digits] per axis: 4 (10 m, default) or 5 (1 m).
/// « 31U DQ 3123 0123 ». Null in the polar areas.
String? formatMgrs(LatLng p,{int digits=4}){
  final u=toUtm(p);
  if(u==null)return null;
  final set=(u.zone-1)%3;
  final col=_colSets[set][((u.easting/100000).floor()-1).clamp(0,7)];
  final rowShift=u.zone.isEven?5:0;
  final row=_rows[((u.northing/100000).floor()+rowShift)%20];
  final div=math.pow(10,5-digits).toInt();
  final e=((u.easting%100000).floor()~/div).toString().padLeft(digits,'0');
  final n=((u.northing%100000).floor()~/div).toString().padLeft(digits,'0');
  return '${u.zone}${u.band} $col$row $e $n';
}

/// « 31UDQ3123401234 », « 31U DQ 31234 01234 », « 31U DQ 3123 0123 »:
/// centre of the designated square.
LatLng? parseMgrs(String text){
  final s=text.toUpperCase().replaceAll(RegExp(r'\s'),'');
  final m=RegExp(r'^(\d{1,2})([C-HJ-NP-X])([A-HJ-NP-Z])([A-HJ-NP-V])(\d*)$').firstMatch(s);
  if(m==null)return null;
  final zone=int.parse(m[1]!), band=m[2]!, colL=m[3]!, rowL=m[4]!, digitsStr=m[5]!;
  if(zone<1||zone>60||digitsStr.length.isOdd||digitsStr.length>10)return null;
  final set=(zone-1)%3;
  final col=_colSets[set].indexOf(colL);
  if(col<0)return null;
  final rowShift=zone.isEven?5:0;
  var row=_rows.indexOf(rowL)-rowShift;
  if(row<0)row+=20;
  final k=digitsStr.length~/2;
  final unit=k==0?100000.0:math.pow(10,5-k).toDouble();
  final e=k==0?0.0:double.parse(digitsStr.substring(0,k))*unit;
  final n=k==0?0.0:double.parse(digitsStr.substring(k))*unit;
  final easting=(col+1)*100000.0+e+unit/2;
  var northing=row*100000.0+n+unit/2;
  // The letters give the northing modulo 2 000 km: the band removes the doubt.
  final north=band.compareTo('N')>=0;
  final bottom=toUtm(LatLng(_bandBottom(band).clamp(-80,84),(zone-1)*6-180+3.0),forceZone:zone)!;
  while(northing<bottom.northing-1000){northing+=2000000;}
  return fromUtm(zone,north,easting,northing);
}
