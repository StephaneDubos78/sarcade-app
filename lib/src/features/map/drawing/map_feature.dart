import 'package:latlong2/latlong.dart';

import 'geometry.dart';

/// Kinds of drawable map objects, matching the drawing toolbar.
enum FeatureKind { point, line, arrow, circle, rectangle, zone, text, freehand, measure }

extension FeatureKindInfo on FeatureKind {
  String get label=>switch(this){
    FeatureKind.point=>'Point',
    FeatureKind.line=>'Ligne',
    FeatureKind.arrow=>'Flèche',
    FeatureKind.circle=>'Cercle',
    FeatureKind.rectangle=>'Rectangle',
    FeatureKind.zone=>'Zone',
    FeatureKind.text=>'Texte',
    FeatureKind.freehand=>'Libre',
    FeatureKind.measure=>'Mesure',
  };

  /// Kinds drawn by tapping several vertices, then finishing explicitly.
  bool get isMultiVertex=>this==FeatureKind.line||this==FeatureKind.arrow||this==FeatureKind.zone||this==FeatureKind.measure;

  /// Kinds rendered as an open line.
  bool get isLinear=>this==FeatureKind.line||this==FeatureKind.arrow||this==FeatureKind.freehand||this==FeatureKind.measure;

  /// Minimum number of vertices for a valid object.
  int get minPoints=>switch(this){
    FeatureKind.point||FeatureKind.text=>1,
    FeatureKind.zone=>3,
    FeatureKind.circle||FeatureKind.rectangle=>2,
    _=>2,
  };
}

/// A structured, georeferenced map object.
///
/// Geometry by kind:
/// - point, text: `points[0]`
/// - line, arrow, freehand, measure: the vertices, in drawing order
/// - zone: the ring vertices, not closed
/// - rectangle: two opposite corners, the four corners are derived
/// - circle: `points[0]` is the centre and [radiusM] the radius
class MapFeature {
  final String id, eventId;
  final FeatureKind kind;
  final List<LatLng> points;
  final double? radiusM;
  final int color;
  final double strokeWidth;
  final String label;
  final String? createdBy;
  /// Author of the last change, tie-break of the conflict rule (ADR-001).
  final String? updatedBy;
  final DateTime updatedAt;

  const MapFeature({required this.id,required this.eventId,required this.kind,required this.points,this.radiusM,required this.color,required this.strokeWidth,this.label='',this.createdBy,this.updatedBy,required this.updatedAt});

  MapFeature copyWith({List<LatLng>? points,double? radiusM,int? color,double? strokeWidth,String? label,String? id,String? updatedBy,DateTime? updatedAt})=>MapFeature(
    id:id??this.id,eventId:eventId,kind:kind,points:points??this.points,radiusM:radiusM??this.radiusM,
    color:color??this.color,strokeWidth:strokeWidth??this.strokeWidth,label:label??this.label,createdBy:createdBy,
    updatedBy:updatedBy??this.updatedBy,updatedAt:updatedAt??DateTime.now().toUtc(),
  );

  /// Vertices of the polygon outline for closed shapes.
  List<LatLng> get ring=>switch(kind){
    FeatureKind.rectangle=>rectangleCorners(points[0],points[1]),
    FeatureKind.zone=>points,
    _=>const [],
  };

  bool get isClosed=>kind==FeatureKind.rectangle||kind==FeatureKind.zone||kind==FeatureKind.circle;

  /// Length in metres for linear objects.
  double get lengthM=>kind.isLinear?pathLength(points):0;

  /// Area in square metres for closed shapes.
  double get areaM2=>switch(kind){
    FeatureKind.circle=>circleArea(radiusM??0),
    FeatureKind.rectangle||FeatureKind.zone=>polygonArea(ring),
    _=>0,
  };

  /// Point used to anchor labels and the move handle.
  LatLng get anchor=>switch(kind){
    FeatureKind.circle||FeatureKind.point||FeatureKind.text=>points[0],
    FeatureKind.rectangle||FeatureKind.zone=>centroid(ring),
    _=>points[points.length~/2],
  };

  /// Same object shifted by a lat/lon delta.
  MapFeature translated(double dLat,double dLon)=>copyWith(points:points.map((p)=>LatLng(p.latitude+dLat,p.longitude+dLon)).toList());

  Map<String,dynamic> toJson()=>{
    'id':id,'event_id':eventId,'kind':kind.name,
    'points':points.map((p)=>[p.latitude,p.longitude]).toList(),
    'radius_m':radiusM,'color':color,'stroke_width':strokeWidth,'label':label,
    'created_by':createdBy,'updated_by':updatedBy??createdBy,'updated_at':updatedAt.toUtc().toIso8601String(),
  };

  factory MapFeature.fromJson(Map<String,dynamic> j)=>MapFeature(
    id:j['id'] as String,eventId:j['event_id'] as String,
    kind:FeatureKind.values.byName(j['kind'] as String),
    points:(j['points'] as List).map((e){final l=e as List;return LatLng((l[0] as num).toDouble(),(l[1] as num).toDouble());}).toList(),
    radiusM:(j['radius_m'] as num?)?.toDouble(),
    color:(j['color'] as num).toInt(),strokeWidth:(j['stroke_width'] as num).toDouble(),
    label:(j['label'] as String?)??'',createdBy:j['created_by'] as String?,updatedBy:j['updated_by'] as String?,
    updatedAt:DateTime.parse(j['updated_at'] as String),
  );

  /// GeoJSON Feature. Coordinates are [longitude, latitude] as the spec requires.
  /// Circles have no GeoJSON geometry: they are exported as a Point with `radius_m`.
  Map<String,dynamic> toGeoJson(){
    List<double> c(LatLng p)=>[p.longitude,p.latitude];
    final geometry=switch(kind){
      FeatureKind.point||FeatureKind.text||FeatureKind.circle=>{'type':'Point','coordinates':c(points[0])},
      FeatureKind.rectangle||FeatureKind.zone=>{'type':'Polygon','coordinates':[[...ring.map(c),c(ring.first)]]},
      _=>{'type':'LineString','coordinates':points.map(c).toList()},
    };
    return {
      'type':'Feature','id':id,'geometry':geometry,
      'properties':{
        'sarcade:kind':kind.name,'event_id':eventId,
        if(label.isNotEmpty)'name':label,
        'stroke':'#${(color&0xFFFFFF).toRadixString(16).padLeft(6,'0')}','stroke-width':strokeWidth,
        if(kind==FeatureKind.circle)'radius_m':radiusM,
        if(kind.isLinear)'length_m':double.parse(lengthM.toStringAsFixed(1)),
        if(isClosed)'area_m2':double.parse(areaM2.toStringAsFixed(1)),
        'updated_at':updatedAt.toUtc().toIso8601String(),
      },
    };
  }
}

Map<String,dynamic> featureCollection(Iterable<MapFeature> features)=>{
  'type':'FeatureCollection',
  'features':features.map((f)=>f.toGeoJson()).toList(),
};
