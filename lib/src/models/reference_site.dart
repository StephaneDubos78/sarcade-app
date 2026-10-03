class ReferenceSite {
  final String id, category, name, source, sourceLayer, status;
  final String? subtype, callsign, access, clearance, mode, ctcssRx, ctcssTx, offset, description, verifiedAt;
  final double lat, lon;
  final double? altM, rxMhz, txMhz;

  const ReferenceSite({
    required this.id,
    required this.category,
    required this.name,
    required this.lat,
    required this.lon,
    required this.source,
    required this.sourceLayer,
    required this.status,
    this.subtype,
    this.callsign,
    this.altM,
    this.access,
    this.clearance,
    this.mode,
    this.rxMhz,
    this.txMhz,
    this.ctcssRx,
    this.ctcssTx,
    this.offset,
    this.description,
    this.verifiedAt,
  });

  bool get isHighPoint => category == 'HIGH_POINT';
  bool get isRelay => category == 'RELAY';

  factory ReferenceSite.fromJson(Map<String,dynamic> j)=>ReferenceSite(
    id:j['id'] as String,
    category:j['category'] as String,
    subtype:j['subtype'] as String?,
    name:j['name'] as String,
    callsign:j['callsign'] as String?,
    lat:(j['lat'] as num).toDouble(),
    lon:(j['lon'] as num).toDouble(),
    altM:(j['alt_m'] as num?)?.toDouble(),
    access:j['access'] as String?,
    clearance:j['clearance'] as String?,
    mode:j['mode'] as String?,
    rxMhz:(j['rx_mhz'] as num?)?.toDouble(),
    txMhz:(j['tx_mhz'] as num?)?.toDouble(),
    ctcssRx:j['ctcss_rx'] as String?,
    ctcssTx:j['ctcss_tx'] as String?,
    offset:j['offset'] as String?,
    description:j['description'] as String?,
    verifiedAt:j['verified_at'] as String?,
    source:j['source'] as String,
    sourceLayer:j['source_layer'] as String,
    status:j['status'] as String,
  );

  Map<String,dynamic> toJson()=>{
    'id':id,'category':category,'subtype':subtype,'name':name,'callsign':callsign,
    'lat':lat,'lon':lon,'alt_m':altM,'access':access,'clearance':clearance,'mode':mode,
    'rx_mhz':rxMhz,'tx_mhz':txMhz,'ctcss_rx':ctcssRx,'ctcss_tx':ctcssTx,'offset':offset,
    'description':description,'verified_at':verifiedAt,'source':source,'source_layer':sourceLayer,'status':status,
  };

  String get subtitle {
    if(isHighPoint){
      final parts=<String>[
        if(altM!=null) '${altM!.toStringAsFixed(0)} m',
        if(subtype?.isNotEmpty==true) subtype!,
      ];
      return parts.join(' · ');
    }
    final parts=<String>[
      if(callsign?.isNotEmpty==true) callsign!,
      if(mode?.isNotEmpty==true) mode!,
      if(txMhz!=null) '${txMhz!.toStringAsFixed(3)} MHz',
    ];
    return parts.join(' · ');
  }
}
