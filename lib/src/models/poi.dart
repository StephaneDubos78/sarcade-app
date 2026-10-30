class SarcadePoi {
  final String id,eventId,kind; final String? label,createdBy,updatedBy,icon; final int? color; final double lat,lon; final DateTime createdAt; final bool deleted;
  const SarcadePoi({required this.id,required this.eventId,required this.kind,required this.lat,required this.lon,required this.createdAt,this.label,this.createdBy,this.updatedBy,this.color,this.icon,this.deleted=false});
  factory SarcadePoi.fromJson(Map<String,dynamic> j)=>SarcadePoi(id:j['id'],eventId:j['event_id'],kind:j['kind']??'designated',label:j['label'],lat:(j['lat'] as num).toDouble(),lon:(j['lon'] as num).toDouble(),createdAt:DateTime.parse(j['created_at']),
    createdBy:j['created_by'] as String?,updatedBy:j['updated_by'] as String?,color:(j['color'] as num?)?.toInt(),icon:j['icon'] as String?,deleted:j['deleted']==true);
  Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'kind':kind,'label':label,'lat':lat,'lon':lon,'created_at':createdAt.toUtc().toIso8601String(),
    if(createdBy!=null)'created_by':createdBy,if(updatedBy!=null)'updated_by':updatedBy,if(color!=null)'color':color,if(icon!=null)'icon':icon};
}
