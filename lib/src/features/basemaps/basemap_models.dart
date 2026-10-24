/// Base maps (note « Choix du fond de carte »): catalog of the server,
/// with the four layers of the first version known offline. Pure code.
library;

const _ignWmts='https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER={layer}'
  '&STYLE=normal&TILEMATRIXSET=PM&FORMAT={fmt}&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

class Basemap {
  final String id, name, attribution; final String? url; final int maxZoom;
  final bool hasOfflinePackage, custom;
  const Basemap({required this.id,required this.name,required this.attribution,this.url,this.maxZoom=19,
    this.hasOfflinePackage=false,this.custom=false});

  factory Basemap.fromJson(Map<String,dynamic> j)=>Basemap(
    id:j['id'] as String,name:(j['name'] as String?)??(j['id'] as String),
    attribution:(j['attribution'] as String?)??'',url:j['url'] as String?,
    maxZoom:(j['max_zoom'] as num?)?.toInt()??19,
    hasOfflinePackage:j['offline_package'] is Map,custom:j['custom']==true);

  Map<String,dynamic> toJson()=>{'id':id,'name':name,'attribution':attribution,'url':url,'max_zoom':maxZoom,
    'offline_package':hasOfflinePackage?{}:null,'custom':custom};

  /// Tiles served by the SARCADE server from the offline package (local
  /// network, no Internet needed).
  String offlineUrl(String serverUrl)=>'$serverUrl/api/v0.1/basemaps/$id/tiles/{z}/{x}/{y}';

  /// URL used by the map: the offline package when asked or when the layer
  /// only exists offline, else the online layer.
  String? tileUrl(String serverUrl,{required bool preferOffline}){
    if(hasOfflinePackage&&(preferOffline||url==null))return offlineUrl(serverUrl);
    return url;
  }
}

/// The four layers of the first version, same as the server catalog.
final builtInBasemaps=[
  const Basemap(id:'osm',name:'OpenStreetMap',attribution:'© OpenStreetMap contributors',url:'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  const Basemap(id:'topo',name:'Topographique',attribution:'© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)',url:'https://tile.opentopomap.org/{z}/{x}/{y}.png',maxZoom:17),
  Basemap(id:'ign-plan',name:'Plan IGN',attribution:'© IGN, Géoplateforme',url:_ignWmts.replaceFirst('{layer}','GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2').replaceFirst('{fmt}','image/png')),
  Basemap(id:'ign-photos',name:'Photographies aériennes IGN',attribution:'© IGN, Géoplateforme',url:_ignWmts.replaceFirst('{layer}','ORTHOIMAGERY.ORTHOPHOTOS').replaceFirst('{fmt}','image/jpeg')),
];

/// Catalog from the server, else the built-in layers.
List<Basemap> mergeCatalog(List<Basemap> fromServer)=>fromServer.isEmpty?builtInBasemaps:fromServer;

/// Layer shown: the operator's choice, else the event default chosen by the
/// PCO, else OpenStreetMap.
Basemap pickBasemap(List<Basemap> catalog,{String? operatorChoice,String? eventDefault}){
  for(final id in [operatorChoice,eventDefault,'osm']){
    if(id==null)continue;
    for(final b in catalog){if(b.id==id)return b;}
  }
  return catalog.isNotEmpty?catalog.first:builtInBasemaps.first;
}
