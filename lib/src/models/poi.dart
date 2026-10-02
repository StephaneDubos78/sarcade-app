class SarcadePoi {
  final String id,eventId,kind; final String? label; final double lat,lon; final DateTime createdAt;
  const SarcadePoi({required this.id,required this.eventId,required this.kind,required this.lat,required this.lon,required this.createdAt,this.label});
  factory SarcadePoi.fromJson(Map<String,dynamic> j)=>SarcadePoi(id:j['id'],eventId:j['event_id'],kind:j['kind'],label:j['label'],lat:(j['lat'] as num).toDouble(),lon:(j['lon'] as num).toDouble(),createdAt:DateTime.parse(j['created_at']));
}
