class SarcadePosition {
  final String id, eventId, deviceId;
  final double lat, lon;
  final double? altM, accuracyM, headingDeg, speedMps;
  final DateTime time;
  const SarcadePosition({required this.id, required this.eventId, required this.deviceId, required this.lat, required this.lon, required this.time, this.altM, this.accuracyM, this.headingDeg, this.speedMps});
  factory SarcadePosition.fromJson(Map<String,dynamic> j)=>SarcadePosition(id:j['id'],eventId:j['event_id'],deviceId:j['device_id'],lat:(j['lat'] as num).toDouble(),lon:(j['lon'] as num).toDouble(),altM:(j['alt_m'] as num?)?.toDouble(),accuracyM:(j['accuracy_m'] as num?)?.toDouble(),headingDeg:(j['heading_deg'] as num?)?.toDouble(),speedMps:(j['speed_mps'] as num?)?.toDouble(),time:DateTime.parse(j['time']));
  Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'device_id':deviceId,'lat':lat,'lon':lon,'alt_m':altM,'accuracy_m':accuracyM,'heading_deg':headingDeg,'speed_mps':speedMps,'time':time.toUtc().toIso8601String()};
}
