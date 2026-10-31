/// Communication group (note « Groupes de communication »): synchronised
/// object with the ADR-001 rule, like map objects. Pure code.
library;

/// Rights given by the server for the email checked by Cloudflare Access
/// (« admin », « pco »), for this device (actor [myActorId]); read at start
/// (GET /me). Without Access, the former rule by terminal name stays.
String? myActorId;
Set<String> myRoles=<String>{};

bool isPco(String actorId)=>actorId=='PCO'||actorId.startsWith('PCO-')||(actorId==myActorId&&myRoles.contains('pco'));

class CommGroup {
  final String id, eventId, name, description, mode, kind, createdBy, updatedBy, radioChannel;
  final int color; final bool archived;
  final List<String> members, roles, senders, managers;
  final String? teamId; final DateTime updatedAt;
  const CommGroup({required this.id,required this.eventId,required this.name,this.description='',this.mode='discussion',
    this.kind='custom',required this.createdBy,required this.updatedBy,this.radioChannel='',this.color=0xFF546E7A,
    this.archived=false,this.members=const [],this.roles=const [],this.senders=const [],this.managers=const [],
    this.teamId,required this.updatedAt});

  static List<String> _list(Object? v)=>v is List?v.whereType<String>().toList():const [];

  factory CommGroup.fromJson(Map<String,dynamic> j)=>CommGroup(
    id:j['id'] as String,eventId:j['event_id'] as String,name:(j['name'] as String?)??'',
    description:(j['description'] as String?)??'',mode:(j['mode'] as String?)??'discussion',
    kind:(j['kind'] as String?)??'custom',createdBy:(j['created_by'] as String?)??'',
    updatedBy:(j['updated_by'] as String?)??'',radioChannel:(j['radio_channel'] as String?)??'',
    color:(j['color'] as num?)?.toInt()??0xFF546E7A,archived:j['archived']==true,
    members:_list(j['members']),roles:_list(j['roles']),senders:_list(j['senders']),managers:_list(j['managers']),
    teamId:j['team_id'] as String?,
    updatedAt:DateTime.tryParse('${j['updated_at']}')??DateTime.fromMillisecondsSinceEpoch(0,isUtc:true),
  );

  Map<String,dynamic> toJson()=>{'id':id,'event_id':eventId,'name':name,'description':description,'mode':mode,
    'kind':kind,'created_by':createdBy,'updated_by':updatedBy,'radio_channel':radioChannel,'color':color,
    'archived':archived,'members':members,'roles':roles,'senders':senders,'managers':managers,'team_id':teamId,
    'updated_at':updatedAt.toUtc().toIso8601String()};

  bool get listenOnly=>mode=='listen_only';
  String get recipientId=>'group:$id';

  /// Same rule as the server: managers and the PCO change a group.
  bool canManage(String actorId)=>isPco(actorId)||managers.contains(actorId);

  /// Same rule as the server: a listen-only group accepts its senders, its
  /// managers and the PCO; an archived group accepts nothing.
  bool canSend(String actorId){
    if(archived)return false;
    if(!listenOnly)return true;
    return isPco(actorId)||senders.contains(actorId)||managers.contains(actorId);
  }

  CommGroup copyWith({String? name,String? description,String? mode,int? color,bool? archived,List<String>? members,
      List<String>? senders,String? radioChannel,required String updatedBy,required DateTime updatedAt})=>CommGroup(
    id:id,eventId:eventId,name:name??this.name,description:description??this.description,mode:mode??this.mode,
    kind:kind,createdBy:createdBy,updatedBy:updatedBy,radioChannel:radioChannel??this.radioChannel,
    color:color??this.color,archived:archived??this.archived,members:members??this.members,roles:roles,
    senders:senders??this.senders,managers:managers,teamId:teamId,updatedAt:updatedAt);
}

/// Default channels in display order (server: groups.service.DEFAULT_GROUPS).
const defaultGroupOrder=['Diffusion PCO','PCO','Équipes terrain','Transmissions','Logistique'];

/// Groups shown to choose a recipient: not archived, « Tous » first, then by name.
List<CommGroup> sortedGroups(Iterable<CommGroup> groups,{bool includeArchived=false}){
  final list=groups.where((g)=>includeArchived||!g.archived).toList();
  // Fixed order of the default channels (card « Ordre des pastilles de
  // groupes », 31 Oct 2026): Tous, Diffusion PCO, PCO, Équipes terrain,
  // Transmissions, Logistique; then teams, then the others by name.
  int rank(CommGroup g){
    if(g.kind=='all')return 0;
    if(g.kind=='default'){final i=defaultGroupOrder.indexOf(g.name);return i<0?1+defaultGroupOrder.length:1+i;}
    return g.kind=='team'?10:11;
  }
  list.sort((a,b){final r=rank(a).compareTo(rank(b));return r!=0?r:a.name.toLowerCase().compareTo(b.name.toLowerCase());});
  return list;
}

/// Messages of a conversation: addressed to the group.
bool messageInGroup(List<String> recipientIds,String groupId)=>recipientIds.contains('group:$groupId');

/// Comma or space separated ids typed in a field.
List<String> parseIds(String text)=>text.split(RegExp(r'[,;\s]+')).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toSet().toList();

/// Whether a message concerns this terminal: broadcast, direct, or a group
/// it belongs to. Until roles exist (ADR-002), a group without explicit
/// members (default groups by role) concerns everyone.
bool addressedTo(List<String> recipientIds,String deviceId,Map<String,CommGroup> groups){
  if(recipientIds.isEmpty)return true;
  for(final r in recipientIds){
    if(r==deviceId||r=='user:$deviceId')return true;
    if(r.startsWith('group:')){
      final g=groups[r.substring(6)];
      if(g==null||g.members.isEmpty||g.members.contains(deviceId))return true;
    }
  }
  return false;
}
