class SarcadePosition {
  final String id, eventId, deviceId;
  final double lat, lon;
  final double? altM, accuracyM, headingDeg, speedMps;
  final DateTime time;
  /// « device » (SARCADE app) or « aprs » (station heard by radio or on
  /// APRS-IS, only for the callsigns followed by the event).
  final String source;
  final String? callsign, aprsVia;
  const SarcadePosition({required this.id, required this.eventId, required this.deviceId, required this.lat, required this.lon, required this.time, this.altM, this.accuracyM, this.headingDeg, this.speedMps,
    this.source='device', this.callsign, this.aprsVia});
  factory SarcadePosition.fromJson(Map<String,dynamic> j)=>SarcadePosition(id:j['id'],eventId:j['event_id'],deviceId:j['device_id'],lat:(j['lat'] as num).toDouble(),lon:(j['lon'] as num).toDouble(),altM:(j['alt_m'] as num?)?.toDouble(),accuracyM:(j['accuracy_m'] as num?)?.toDouble(),headingDeg:(j['heading_deg'] as num?)?.toDouble(),speedMps:(j['speed_mps'] as num?)?.toDouble(),time:DateTime.parse(j['time']),
    source:(j['source'] as String?)??'device',callsign:j['callsign'] as String?,aprsVia:j['aprs_via'] as String?);
  Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'device_id':deviceId,'lat':lat,'lon':lon,'alt_m':altM,'accuracy_m':accuracyM,'heading_deg':headingDeg,'speed_mps':speedMps,'time':time.toUtc().toIso8601String(),
    if(source!='device')'source':source,if(callsign!=null)'callsign':callsign,if(aprsVia!=null)'aprs_via':aprsVia};
  bool get isAprs=>source=='aprs';
  /// Name shown on the map: the terminal (an APRS position linked to an
  /// operator's callsign keeps the terminal name), or the callsign of a
  /// station without terminal.
  String get label=>deviceId.startsWith('aprs:')?(callsign??deviceId.substring(5)):deviceId;
}
