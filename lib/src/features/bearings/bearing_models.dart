/// Radio direction-finding bearings (note « Relevés et croisements »,
/// decisions of 23 Oct 2026; screen of the interface V2, 27 Oct 2026).
/// A bearing is a map object of kind « bearing » (server: map_feature):
/// a line from where it was taken, along the true azimuth, 10 km long by
/// default, with a ±5° cone. Crossings and the probable zone are computed
/// on every device from the bearings of the same search.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../map/drawing/geometry.dart' as geo;

class Bearing {
  final String id, eventId, createdBy, updatedBy;
  final LatLng origin;
  final double azimuthDeg, lengthM, coneDeg;
  final int strength; // 0 = not given, else S1..S9
  final String target, comment, search, method;
  final double? magneticDeg, declinationDeg, accuracyM;
  /// Colour of the operator who took it (dot where it was taken).
  final int? operatorColor;
  /// Signal of an exercise beacon (badge « EXERCICE »), and its frequency.
  final bool exercise;
  final double? frequencyMhz;
  final DateTime takenAt, updatedAt;
  /// In the probable zone, decided by hand by the PCO (card « Zone
  /// probable », 31 Oct 2026): 'in' always kept, 'out' set aside, 'auto'.
  final String zone;
  const Bearing({this.zone='auto',required this.id,required this.eventId,required this.origin,required this.azimuthDeg,
    this.lengthM=10000,this.coneDeg=5,this.strength=0,this.target='',this.comment='',this.search='',this.method='manual',
    this.magneticDeg,this.declinationDeg,this.accuracyM,this.operatorColor,this.exercise=false,this.frequencyMhz,required this.takenAt,required this.createdBy,required this.updatedBy,required this.updatedAt});

  static bool isBearing(Map<String,dynamic> j)=>j['kind']=='bearing';

  factory Bearing.fromJson(Map<String,dynamic> j){
    final b=Map<String,dynamic>.from(j['bearing'] as Map);
    final p=(j['points'] as List).first as List;
    double? n(Object? v)=>(v as num?)?.toDouble();
    final updated=DateTime.parse(j['updated_at'] as String);
    return Bearing(id:j['id'] as String,eventId:j['event_id'] as String,origin:LatLng((p[0] as num).toDouble(),(p[1] as num).toDouble()),
      azimuthDeg:n(b['azimuth_deg'])!,lengthM:n(b['length_m'])??10000,coneDeg:n(b['cone_deg'])??5,strength:(b['strength'] as num?)?.toInt()??0,
      target:'',comment:legacyComment((b['target'] as String?)??'',(b['comment'] as String?)??''),search:(b['search'] as String?)??'',method:(b['method'] as String?)??'manual',
      magneticDeg:n(b['magnetic_deg']),declinationDeg:n(b['declination_deg']),accuracyM:n(b['accuracy_m']),operatorColor:(b['operator_color'] as num?)?.toInt(),
      exercise:b['exercise']==true,frequencyMhz:n(b['frequency_mhz']),
      zone:const {'in','out'}.contains(b['zone'])?b['zone'] as String:'auto',
      takenAt:DateTime.tryParse('${b['taken_at']??''}')??updated,
      createdBy:(j['created_by'] as String?)??(j['updated_by'] as String),updatedBy:j['updated_by'] as String,updatedAt:updated);
  }

  /// Payload of the map_feature operation.
  Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'kind':'bearing','points':[[origin.latitude,origin.longitude]],
    'color':searchColor(search),'stroke_width':2.0,'label':search,'created_by':createdBy,'updated_by':updatedBy,
    'updated_at':updatedAt.toUtc().toIso8601String(),
    'bearing':{'azimuth_deg':azimuthDeg,'length_m':lengthM,'cone_deg':coneDeg,'strength':strength,'target':target,'comment':comment,
      'search':search,'method':method,'taken_at':takenAt.toUtc().toIso8601String(),
      if(magneticDeg!=null)'magnetic_deg':magneticDeg,if(declinationDeg!=null)'declination_deg':declinationDeg,if(accuracyM!=null)'accuracy_m':accuracyM,if(operatorColor!=null)'operator_color':operatorColor,
      if(exercise)'exercise':true,if(frequencyMhz!=null)'frequency_mhz':frequencyMhz,if(zone!='auto')'zone':zone}};

  Bearing copyWith({double? azimuthDeg,double? coneDeg,double? lengthM,int? strength,String? target,String? comment,String? search,
      LatLng? origin,String? method,DateTime? takenAt,bool? exercise,double? frequencyMhz,String? zone,
      required String updatedBy,required DateTime updatedAt})=>Bearing(zone:zone??this.zone,id:id,eventId:eventId,origin:origin??this.origin,
    azimuthDeg:azimuthDeg??this.azimuthDeg,lengthM:lengthM??this.lengthM,coneDeg:coneDeg??this.coneDeg,strength:strength??this.strength,
    target:target??this.target,comment:comment??this.comment,search:search??this.search,method:method??this.method,magneticDeg:magneticDeg,
    declinationDeg:declinationDeg,accuracyM:accuracyM,operatorColor:operatorColor,exercise:exercise??this.exercise,frequencyMhz:frequencyMhz??this.frequencyMhz,takenAt:takenAt??this.takenAt,createdBy:createdBy,updatedBy:updatedBy,updatedAt:updatedAt);

  LatLng get end=>geo.destination(origin,lengthM,azimuthDeg);
  /// The two edges of the uncertainty cone.
  (LatLng,LatLng) get cone=>(geo.destination(origin,lengthM,(azimuthDeg-coneDeg+360)%360),geo.destination(origin,lengthM,(azimuthDeg+coneDeg)%360));

  /// Author or PCO may change or delete it (decision 5).
  bool canEdit(String actor,bool isPco)=>actor==createdBy||isPco;
}

/// Fixed colours of the beacons (decision of 29 Oct 2026, 17 h 05):
/// 406 MHz violet, 121,5 MHz red, exercise 121,375 MHz blue.
const beacon406Color=0xFF9B4DFF, beacon1215Color=0xFFE53935, beaconExerciseColor=0xFF1E88E5;

/// Beacon colour read from the search name (« 121,500 MHz · … », « Balise 406 – 23/10 »), else null.
int? beaconColor(String search){
  final m=RegExp(r'(\d{3})(?:[.,](\d+))?').allMatches(search);
  for(final x in m){
    final f=double.tryParse('${x.group(1)}.${x.group(2)??'0'}');
    if(f==null)continue;
    if(f>=406&&f<407)return beacon406Color;
    if((f-121.375).abs()<0.001)return beaconExerciseColor;
    if((f-121.5).abs()<0.001)return beacon1215Color;
  }
  return null;
}

/// One colour per search, stable from its name; the beacons have their own
/// colours, which the palette avoids (no violet, red or plain blue).
int searchColor(String search){
  final b=beaconColor(search); if(b!=null)return b;
  const palette=[0xFF3DD6F5,0xFFFFB020,0xFF4ADE80,0xFFFF7AB6,0xFFFFE066];
  var h=0; for(final c in search.codeUnits){h=(h*31+c)&0x7FFFFFFF;}
  return palette[search.isEmpty?0:h%palette.length];
}

/// Intersection of two bearing lines (segments), planar around them (lines
/// of at most a few hundred km); null when parallel or not crossing.
LatLng? crossing(Bearing a,Bearing b){
  final lat0=(a.origin.latitude+b.origin.latitude)/2*math.pi/180;
  final k=math.cos(lat0);
  math.Point<double> xy(LatLng p)=>math.Point(p.longitude*k,p.latitude);
  final p1=xy(a.origin),p2=xy(a.end),p3=xy(b.origin),p4=xy(b.end);
  final d=(p2.x-p1.x)*(p4.y-p3.y)-(p2.y-p1.y)*(p4.x-p3.x);
  if(d.abs()<1e-12)return null;
  final t=((p3.x-p1.x)*(p4.y-p3.y)-(p3.y-p1.y)*(p4.x-p3.x))/d;
  final u=((p3.x-p1.x)*(p2.y-p1.y)-(p3.y-p1.y)*(p2.x-p1.x))/d;
  if(t<0||t>1||u<0||u>1)return null;
  return LatLng(p1.y+t*(p2.y-p1.y),(p1.x+t*(p2.x-p1.x))/k);
}

/// Robust probable zone (card « Zone probable : libellé trop gros et
/// relevés incohérents », validated 31 Oct 2026, 11 h 07). Same rule as
/// `robust_zone` of the server (tv.py), keep in step:
/// - crossings of nearly parallel bearings (< 20°) are ignored;
/// - each crossing weighs the precision of both bearings (1 / cone²), the
///   signal strength and the sine of their angle;
/// - bearings set aside by hand ('out') are left out; with 3 or more, each
///   bearing is tested against the zone of the others, and the worst one
///   beyond its error cone is set aside, again until all agree; bearings
///   kept by hand ('in') always stay;
/// - radius: distance holding ~90 % of the weighted crossings (≥ 50 m).
/// [robust] false: the plain rule (résection: every crossing, farthest).
const minCrossingAngleDeg=20.0, minZoneToleranceM=100.0, minZoneRadiusM=50.0, zoneShare=0.9;

double _weight(Bearing b)=>(1+b.strength/9)/math.pow(math.max(1.0,b.coneDeg),2);
double _angleBetween(Bearing a,Bearing b){final d=(a.azimuthDeg-b.azimuthDeg).abs()%180;return math.min(d,180-d);}

List<({LatLng p,double w})> _weightedCrossings(List<Bearing> g,Set<int> used,{required bool robust}){
  final ids=used.toList()..sort(); final out=<({LatLng p,double w})>[];
  for(var x=0;x<ids.length;x++){for(var y=x+1;y<ids.length;y++){
    final a=g[ids[x]], b=g[ids[y]]; final ang=_angleBetween(a,b);
    if(robust&&ang<minCrossingAngleDeg)continue;
    final c=crossing(a,b); if(c==null)continue;
    out.add((p:c,w:robust?_weight(a)*_weight(b)*math.sin(ang*math.pi/180):1.0));
  }}
  return out;
}

LatLng _wCentre(List<({LatLng p,double w})> pts){
  final w=pts.fold<double>(0,(s,e)=>s+e.w);
  return LatLng(pts.fold<double>(0,(s,e)=>s+e.p.latitude*e.w)/w,pts.fold<double>(0,(s,e)=>s+e.p.longitude*e.w)/w);
}

double _wRadius(LatLng c,List<({LatLng p,double w})> pts){
  final d=[for(final e in pts)(d:geo.distanceM(c,e.p),w:e.w)]..sort((a,b)=>a.d.compareTo(b.d));
  final total=d.fold<double>(0,(s,e)=>s+e.w); var acc=0.0;
  for(final e in d){acc+=e.w;if(acc>=zoneShare*total)return math.max(minZoneRadiusM,e.d);}
  return math.max(minZoneRadiusM,d.last.d);
}

/// Distance from the line of [b] to [c], and distance along it.
({double miss,double along}) _miss(Bearing b,LatLng c){
  final k=math.cos(b.origin.latitude*math.pi/180);
  final dx=(c.longitude-b.origin.longitude)*k*111320.0, dy=(c.latitude-b.origin.latitude)*110540.0;
  final az=b.azimuthDeg*math.pi/180, ux=math.sin(az), uy=math.cos(az);
  final along=dx*ux+dy*uy;
  if(along<=0)return (miss:math.sqrt(dx*dx+dy*dy),along:0);
  return (miss:(dx*uy-dy*ux).abs(),along:along);
}

({List<LatLng> crossings,LatLng? centre,double radiusM,int bearings,List<String> excluded,List<String> autoExcluded}) probableZone(List<Bearing> list,{bool robust=true}){
  final used=<int>{for(var i=0;i<list.length;i++)if(!robust||list[i].zone!='out')i};
  final auto=<int>[];
  while(robust&&used.length>=3){
    int? worst; var worstRatio=1.0;
    for(final i in used.toList()..sort()){
      if(list[i].zone=='in')continue;
      final others=_weightedCrossings(list,used.difference({i}),robust:true);
      if(others.isEmpty)continue;
      final c=_wCentre(others); final m=_miss(list[i],c);
      final tol=math.max(minZoneToleranceM,m.along*math.tan(math.max(list[i].coneDeg,1)*math.pi/180))+0.5*_wRadius(c,others);
      if(m.miss/tol>worstRatio){worst=i;worstRatio=m.miss/tol;}
    }
    if(worst==null)break;
    used.remove(worst); auto.add(worst);
  }
  final pts=_weightedCrossings(list,used,robust:robust);
  final excluded=[for(var i=0;i<list.length;i++)if(!used.contains(i))list[i].id];
  final autoIds=[for(final i in auto)list[i].id];
  if(pts.isEmpty)return (crossings:const <LatLng>[],centre:null,radiusM:0,bearings:used.length,excluded:excluded,autoExcluded:autoIds);
  final c=_wCentre(pts);
  final r=robust?_wRadius(c,pts):math.max(minZoneRadiusM,pts.map((e)=>geo.distanceM(c,e.p)).fold<double>(0,math.max));
  return (crossings:[for(final e in pts)e.p],centre:c,radiusM:r,bearings:used.length,excluded:excluded,autoExcluded:autoIds);
}

/// « ±700 m · 4 relevés · 1 écarté » (server: tv.zone_label).
String zoneLabel(double radiusM,int used,int excluded)=>[
  '±${roundedDistance(radiusM)}',
  S.t(used==1?'bearings.zoneOne':'bearings.zoneMany',{'n':used}),
  if(excluded>0)S.t(excluded==1?'bearings.zoneExcludedOne':'bearings.zoneExcludedMany',{'n':excluded}),
].join(' · ');

/// Line of the bearing sheet about the probable zone, or null when the
/// bearing simply counts.
String? bearingZoneStatus(Bearing b,Iterable<Bearing> all){
  if(b.zone=='out')return S.t('bearings.excludedHand');
  if(b.zone=='in')return S.t('bearings.keptHand');
  if(b.search.isEmpty)return null;
  final same=all.where((x)=>x.search==b.search).toList();
  final z=probableZone(same);
  if(!z.autoExcluded.contains(b.id))return null;
  return S.t('bearings.excludedAuto',{'n':same.length-1});
}

/// Rounded for a label: « 700 m » rather than « 699 m », « 1,3 km », « 12 km ».
String roundedDistance(double m){
  if(m<1000)return '${(m/10).round()*10} m';
  if(m<10000)return '${(m/1000).toStringAsFixed(1).replaceAll('.',',')} km';
  return '${(m/1000).round()} km';
}

/// Bearings grouped by search, in order of the most recent first.
Map<String,List<Bearing>> bySearch(Iterable<Bearing> list){
  final out=<String,List<Bearing>>{};
  for(final b in list){(out[b.search]??=[]).add(b);}
  return out;
}

/// « Signal recherché » (decision of 28 Oct 2026): the search becomes the
/// signal, the old « Cible » goes into the comment.
String legacyComment(String target,String comment){
  final t=target.trim();
  if(t.isEmpty||comment.contains(t))return comment;
  return comment.isEmpty?t:'$t · $comment';
}

/// Signals already searched in the event, most recent bearing first.
List<String> signalsByRecency(Iterable<Bearing> list){
  final sorted=[...list]..sort((a,b)=>b.takenAt.compareTo(a.takenAt));
  final out=<String>[];
  for(final b in sorted){if(b.search.isNotEmpty&&!out.contains(b.search))out.add(b.search);}
  return out;
}

/// Colour of an operator (dot where a bearing was taken), stable from the
/// identifier, until the operator colours of the event exist.
int operatorColor(String id){
  const palette=[0xFFE53935,0xFFFB8C00,0xFF43A047,0xFF1E88E5,0xFF8E24AA,0xFF00897B,0xFFD81B60,0xFF6D4C41,0xFF3949AB,0xFF7CB342];
  var h=0; for(final c in id.codeUnits){h=(h*31+c)&0x7FFFFFFF;}
  return palette[h%palette.length];
}

/// Initials shown in the dot: callsign or terminal, two characters.
String operatorInitials(String id){
  final t=id.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
  return t.length<=2?t:t.substring(0,2);
}

/// Résection (ATAK 2): position of a team without GPS from the azimuths it
/// measured towards two or three known points (high points, relays). Seen
/// from each known point, the team is in the opposite direction; the
/// crossings of these lines give the position and its uncertainty.
({LatLng? centre,double radiusM}) resection(List<({LatLng known,double azimuthDeg})> sights,{double coneDeg=3}){
  final now=DateTime.utc(2000);
  final lines=[for(var i=0;i<sights.length;i++)Bearing(id:'r$i',eventId:'',origin:sights[i].known,
    azimuthDeg:(sights[i].azimuthDeg+180)%360,lengthM:60000,coneDeg:coneDeg,takenAt:now,createdBy:'',updatedBy:'',updatedAt:now)];
  final z=probableZone(lines,robust:false);
  return (centre:z.centre,radiusM:z.radiusM);
}

/// « 14:05 », local time of a bearing.
String hhmm(DateTime t){final l=t.toLocal();String two(int v)=>v.toString().padLeft(2,'0');return '${two(l.hour)}:${two(l.minute)}';}

/// The same day at the local time typed (« 14:05 », « 14h05 »); unchanged
/// when not understood.
DateTime withHhmm(DateTime t,String text){
  final m=RegExp(r'^\s*(\d{1,2})\s*[:hH.]\s*(\d{2})\s*$').firstMatch(text);
  if(m==null)return t;
  final h=int.parse(m.group(1)!), mi=int.parse(m.group(2)!);
  if(h>23||mi>59)return t;
  final l=t.toLocal();
  return DateTime(l.year,l.month,l.day,h,mi).toUtc();
}
