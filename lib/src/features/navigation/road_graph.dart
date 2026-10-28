/// Navigation on the device (level 3, variant B, decision of 10 Oct 2026):
/// compact road graph prepared by the server (« SRG1 » package) and
/// itinerary computed here, without network, on every platform. Pure Dart.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import '../map/drawing/geometry.dart';
import '../routes/route_models.dart';

const _modeBits={'car':1,'foot':2,'offroad':4};

class RoadGraph {
  final Map<String,dynamic> header;
  final Float64List vLat, vLon;
  final Uint32List eFrom, eTo, eName, eGeomStart;
  final Float64List eLength;
  final Uint8List eFwd, eBwd;
  final Uint16List eClass, eGeomCount;
  final Float64List gLat, gLon;
  final List<String> names, classes;
  final Map<String,List<double>> speedsKmh;
  late final List<List<int>> _adjacency=_buildAdjacency();

  RoadGraph._(this.header,this.vLat,this.vLon,this.eFrom,this.eTo,this.eName,this.eGeomStart,this.eLength,this.eFwd,
    this.eBwd,this.eClass,this.eGeomCount,this.gLat,this.gLon,this.names,this.classes,this.speedsKmh);

  int get vertexCount=>vLat.length;
  int get edgeCount=>eFrom.length;
  String get builtAt=>'${header['built_at']??''}';
  String get attribution=>'${header['attribution']??'© OpenStreetMap contributors'}';

  /// Reads a package as served by `GET /api/v0.1/routing/graph`.
  factory RoadGraph.parse(List<int> gzipped){
    final raw=Uint8List.fromList(GZipDecoder().decodeBytes(gzipped));
    final data=ByteData.sublistView(raw);
    if(raw.length<8||utf8.decode(raw.sublist(0,4))!='SRG1')throw const FormatException('not_srg1');
    final hlen=data.getUint32(4,Endian.little);
    final header=Map<String,dynamic>.from(jsonDecode(utf8.decode(raw.sublist(8,8+hlen))) as Map);
    var pos=8+hlen;
    final nv=(header['vertices'] as num).toInt(), ne=(header['edges'] as num).toInt(), ng=(header['geometry_points'] as num).toInt();
    final vLat=Float64List(nv), vLon=Float64List(nv);
    for(var i=0;i<nv;i++){vLat[i]=data.getInt32(pos,Endian.little)/1e6;vLon[i]=data.getInt32(pos+4,Endian.little)/1e6;pos+=8;}
    final eFrom=Uint32List(ne), eTo=Uint32List(ne), eName=Uint32List(ne), eGs=Uint32List(ne);
    final eLen=Float64List(ne); final eFwd=Uint8List(ne), eBwd=Uint8List(ne); final eCls=Uint16List(ne), eGc=Uint16List(ne);
    for(var i=0;i<ne;i++){
      eFrom[i]=data.getUint32(pos,Endian.little); eTo[i]=data.getUint32(pos+4,Endian.little);
      eLen[i]=data.getUint32(pos+8,Endian.little)/10; eFwd[i]=data.getUint8(pos+12); eBwd[i]=data.getUint8(pos+13);
      eCls[i]=data.getUint16(pos+14,Endian.little); eName[i]=data.getUint32(pos+16,Endian.little);
      eGs[i]=data.getUint32(pos+20,Endian.little); eGc[i]=data.getUint16(pos+24,Endian.little);
      pos+=26;
    }
    final gLat=Float64List(ng), gLon=Float64List(ng);
    for(var i=0;i<ng;i++){gLat[i]=data.getInt32(pos,Endian.little)/1e6;gLon[i]=data.getInt32(pos+4,Endian.little)/1e6;pos+=8;}
    final count=data.getUint32(pos,Endian.little); pos+=4;
    final names=<String>[];
    for(var i=0;i<count;i++){final n=data.getUint16(pos,Endian.little);names.add(utf8.decode(raw.sublist(pos+2,pos+2+n)));pos+=2+n;}
    final classes=[for(final c in (header['classes'] as List))'$c'];
    final speeds=<String,List<double>>{};
    (header['speeds_kmh'] as Map).forEach((k,v){speeds['$k']=[for(final s in (v as List))(s as num).toDouble()];});
    return RoadGraph._(header,vLat,vLon,eFrom,eTo,eName,eGs,eLen,eFwd,eBwd,eCls,eGc,gLat,gLon,names,classes,speeds);
  }

  List<List<int>> _buildAdjacency(){
    final adj=List<List<int>>.generate(vertexCount,(_)=><int>[]);
    // Encoded as edge*2 (+1 when travelled backwards).
    for(var e=0;e<edgeCount;e++){adj[eFrom[e]].add(e*2);adj[eTo[e]].add(e*2+1);}
    return adj;
  }

  LatLng vertex(int i)=>LatLng(vLat[i],vLon[i]);

  /// Points of an edge in the travel direction.
  List<LatLng> edgePoints(int e,{bool backward=false}){
    final pts=<LatLng>[vertex(eFrom[e])];
    for(var k=0;k<eGeomCount[e];k++){pts.add(LatLng(gLat[eGeomStart[e]+k],gLon[eGeomStart[e]+k]));}
    pts.add(vertex(eTo[e]));
    return backward?pts.reversed.toList():pts;
  }

  double _speedMs(int e,String mode){
    final kmh=speedsKmh[mode]?[eClass[e]]??0;
    return kmh/3.6;
  }

  bool _allowed(int e,bool backward,String mode){
    final bit=_modeBits[mode]??0;
    return ((backward?eBwd[e]:eFwd[e])&bit)!=0&&_speedMs(e,mode)>0;
  }

  /// Nearest vertex reachable in [mode] (equirectangular distance).
  int? nearestVertex(LatLng p,String mode){
    final cosLat=math.cos(p.latitude*math.pi/180);
    int? best; var bestD=double.infinity;
    final usable=List<bool>.filled(vertexCount,false);
    for(var e=0;e<edgeCount;e++){
      if(_allowed(e,false,mode)||_allowed(e,true,mode)){usable[eFrom[e]]=true;usable[eTo[e]]=true;}
    }
    for(var i=0;i<vertexCount;i++){
      if(!usable[i])continue;
      final dy=vLat[i]-p.latitude, dx=(vLon[i]-p.longitude)*cosLat;
      final d=dx*dx+dy*dy;
      if(d<bestD){bestD=d;best=i;}
    }
    return best;
  }

  /// Edges passing within [marginM] of a closed road (avoided).
  Set<int> blockedEdges(List<List<LatLng>> closures,{double marginM=15}){
    final blocked=<int>{};
    if(closures.isEmpty)return blocked;
    for(var e=0;e<edgeCount;e++){
      final pts=edgePoints(e);
      for(final line in closures){
        if(_near(pts,line,marginM)){blocked.add(e);break;}
      }
    }
    return blocked;
  }

  /// Edge [a] runs along the closed road [b]. Only the inner points and
  /// segment middles are compared, so that the roads meeting the closure at
  /// its ends stay open.
  static bool _near(List<LatLng> a,List<LatLng> b,double marginM){
    List<LatLng> inner(List<LatLng> l)=>[
      for(var i=1;i<l.length;i++)LatLng((l[i-1].latitude+l[i].latitude)/2,(l[i-1].longitude+l[i].longitude)/2),
      for(var i=1;i<l.length-1;i++)l[i],
    ];
    for(final p in inner(b)){for(var i=1;i<a.length;i++){if(_pointSegmentM(p,a[i-1],a[i])<=marginM)return true;}}
    for(final p in inner(a)){for(var i=1;i<b.length;i++){if(_pointSegmentM(p,b[i-1],b[i])<=marginM)return true;}}
    return false;
  }

  static double _pointSegmentM(LatLng p,LatLng a,LatLng b){
    final cosLat=math.cos(p.latitude*math.pi/180);
    const m=111320.0;
    final ax=(a.longitude-p.longitude)*cosLat*m, ay=(a.latitude-p.latitude)*m;
    final bx=(b.longitude-p.longitude)*cosLat*m, by=(b.latitude-p.latitude)*m;
    final dx=bx-ax, dy=by-ay;
    final len2=dx*dx+dy*dy;
    var t=len2==0?0.0:-(ax*dx+ay*dy)/len2;
    t=t.clamp(0.0,1.0);
    final x=ax+t*dx, y=ay+t*dy;
    return math.sqrt(x*x+y*y);
  }

  /// A* on travel time. Returns the edges (encoded) from [a] to [b], or null.
  List<int>? shortestPath(int a,int b,String mode,{Set<int> blocked=const {}}){
    if(a==b)return <int>[];
    final maxKmh=(speedsKmh[mode]??const [5.0]).fold<double>(1,math.max);
    final maxMs=maxKmh/3.6;
    final target=vertex(b);
    double h(int v)=>distanceM(vertex(v),target)/maxMs;
    final g=<int,double>{a:0}; final via=<int,int>{};
    final open=_Heap()..push(h(a),a);
    final closed=<int>{};
    while(open.isNotEmpty){
      final u=open.pop();
      if(u==b){
        final path=<int>[]; var v=b;
        while(v!=a){final code=via[v]!;path.add(code);final e=code>>1;v=(code&1)==0?eFrom[e]:eTo[e];}
        return path.reversed.toList();
      }
      if(!closed.add(u))continue;
      for(final code in _adjacency[u]){
        final e=code>>1, backward=(code&1)==1;
        if(blocked.contains(e)||!_allowed(e,backward,mode))continue;
        final v=backward?eFrom[e]:eTo[e];
        final cost=g[u]!+eLength[e]/_speedMs(e,mode);
        if(cost<(g[v]??double.infinity)){g[v]=cost;via[v]=code;open.push(cost+h(v),v);}
      }
    }
    return null;
  }

  /// Itinerary from [from] to [to] computed on the device: approach in a
  /// straight line to the nearest usable point of the graph, roads, then
  /// straight line to the destination. Null when no itinerary exists.
  Itinerary? route(LatLng from,LatLng to,String mode,{List<List<LatLng>> closures=const [],
      String Function(String key,Map<String,Object?> args)? t}){
    final a=nearestVertex(from,mode), b=nearestVertex(to,mode);
    if(a==null||b==null)return null;
    final path=shortestPath(a,b,mode,blocked:blockedEdges(closures));
    if(path==null)return null;
    final geometry=<LatLng>[from];
    var duration=distanceM(from,vertex(a))/1.2;
    final steps=<({int edge,bool backward,int beginIndex})>[];
    for(final code in path){
      final e=code>>1, backward=(code&1)==1;
      steps.add((edge:e,backward:backward,beginIndex:geometry.length-1));
      final pts=edgePoints(e,backward:backward);
      if(geometry.isNotEmpty&&geometry.last==pts.first){geometry.addAll(pts.skip(1));}else{geometry.addAll(pts);}
      duration+=eLength[e]/_speedMs(e,mode);
    }
    final lastWalk=distanceM(vertex(b),to);
    duration+=lastWalk/1.2;
    if(lastWalk>1)geometry.add(to);
    final maneuvers=t==null?const <({String instruction,double lengthM,int beginIndex})>[]:_maneuvers(steps,t);
    return Itinerary(geometry:geometry,lengthM:pathLength(geometry),durationS:duration,maneuvers:maneuvers,onDevice:true);
  }

  /// Simple instructions: start, turns where the way changes name or turns
  /// by more than 30°, arrival.
  List<({String instruction,double lengthM,int beginIndex})> _maneuvers(
      List<({int edge,bool backward,int beginIndex})> steps,String Function(String key,Map<String,Object?> args) t){
    final out=<({String instruction,double lengthM,int beginIndex})>[];
    if(steps.isEmpty){return [(instruction:t('nav.step.arrive',const {}),lengthM:0.0,beginIndex:0)];}
    String name(int e){final n=names[eName[e]];return n.isEmpty?t('nav.step.unnamed',const {}):n;}
    var currentStart=steps.first.beginIndex; var length=0.0;
    var label=t('nav.step.start',{'name':name(steps.first.edge)});
    for(var i=0;i<steps.length;i++){
      final s=steps[i];
      if(i>0){
        final prev=steps[i-1];
        final pin=edgePoints(prev.edge,backward:prev.backward), pout=edgePoints(s.edge,backward:s.backward);
        final inBearing=bearingDeg(pin[pin.length-2],pin.last), outBearing=bearingDeg(pout.first,pout[1]);
        final turn=((outBearing-inBearing+540)%360)-180;
        final renamed=eName[prev.edge]!=eName[s.edge];
        if(turn.abs()>30||renamed){
          out.add((instruction:label,lengthM:length,beginIndex:currentStart));
          final dir=turn.abs()<=30?'straight':(turn>0?(turn>120?'sharpRight':'right'):(turn< -120?'sharpLeft':'left'));
          label=t('nav.step.$dir',{'name':name(s.edge)});
          currentStart=s.beginIndex; length=0;
        }
      }
      length+=eLength[s.edge];
    }
    out.add((instruction:label,lengthM:length,beginIndex:currentStart));
    out.add((instruction:t('nav.step.arrive',const {}),lengthM:0.0,beginIndex:steps.last.beginIndex+1));
    return out;
  }
}

/// Binary heap of (priority, vertex).
class _Heap {
  final _p=<double>[]; final _v=<int>[];
  bool get isNotEmpty=>_p.isNotEmpty;
  void push(double p,int v){
    _p.add(p);_v.add(v);
    var i=_p.length-1;
    while(i>0){final parent=(i-1)>>1;if(_p[parent]<=_p[i])break;_swap(i,parent);i=parent;}
  }
  int pop(){
    final top=_v[0];
    final lastP=_p.removeLast(), lastV=_v.removeLast();
    if(_p.isNotEmpty){
      _p[0]=lastP;_v[0]=lastV;
      var i=0;
      while(true){
        final l=2*i+1, r=l+1; var m=i;
        if(l<_p.length&&_p[l]<_p[m])m=l;
        if(r<_p.length&&_p[r]<_p[m])m=r;
        if(m==i)break;
        _swap(i,m);i=m;
      }
    }
    return top;
  }
  void _swap(int a,int b){final p=_p[a];_p[a]=_p[b];_p[b]=p;final v=_v[a];_v[a]=_v[b];_v[b]=v;}
}
