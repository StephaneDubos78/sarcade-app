/// « 1 élément(s) non envoyé(s) » on the iPhone (card of 30 Oct 2026,
/// validated 10 h 27): pure helpers, testable without Flutter.
/// 0) « Envoyer » of the banner = « Tout réessayer »: items set aside go
///    back to the queue too ([retryAllOf]);
/// 1) the banner says what is blocked (« 1 photo non envoyée », [unsentWhat]);
/// 2) the list gives the reason of the server in plain words ([readableReason]);
/// 3) when sending fails again, Supprimer or Exporter are offered.
library;

import '../l10n/strings.dart';
import 'outbox_policy.dart';

/// Kind of a blocked item, for the banner: photo, message, position,
/// map_feature, bearing, poi, delete or other.
String unsentKind(Map<String,dynamic> op){
  final p=op['payload'] is Map?op['payload'] as Map:const {};
  final type=op['object_type'];
  if(op['action']=='delete')return 'delete';
  if(type=='message'){final a=p['attachments'];return a is List&&a.isNotEmpty?'photo':'message';}
  if(type=='map_feature')return p['kind']=='bearing'||p['bearing'] is Map?'bearing':'map_feature';
  return const {'position','poi'}.contains(type)?'$type':'other';
}

/// « 1 photo non envoyée », « 2 messages non envoyés · 1 position non
/// envoyée »: the two most frequent kinds, then « +n ».
String unsentWhat(Iterable<Map<String,dynamic>> items){
  final count=<String,int>{};
  for(final op in items){final k=unsentKind(op);count[k]=(count[k]??0)+1;}
  if(count.isEmpty)return '';
  final kinds=count.keys.toList()..sort((a,b){final c=count[b]!.compareTo(count[a]!);return c!=0?c:a.compareTo(b);});
  final shown=[for(final k in kinds.take(2))S.t('unsent.what.$k',{'n':count[k]})];
  final rest=kinds.skip(2).fold<int>(0,(s,k)=>s+count[k]!);
  return [...shown,if(rest>0)'+$rest'].join(' · ');
}

/// « Tout réessayer »: every item of this server and event that is not on
/// its way (set aside by the server, or failing for too long) goes back to
/// the queue with its counters reset. The items of another server or event
/// stay where they are.
List<Map<String,dynamic>> retryAllOf(List<Map<String,dynamic>> all,String server,String eventId,DateTime now)=>[
  for(final op in all)if(belongsTo(op,server,eventId)&&(isSetAside(op)||isUnsent(op,server,eventId,now)))resetForRetry(op)];

/// Reason shown in the list: « Refusé par le serveur : objet cartographique
/// invalide » for an item set aside, the plain reason otherwise (« erreur
/// du serveur (500) »); null when there is none.
String? readableReason(Map<String,dynamic> op){
  final r=(reasonOf(op)??'').trim();
  if(!isSetAside(op))return r.isEmpty?null:r;
  return r.isEmpty||r=='refusé par le serveur'?S.t('unsent.refusedPlain'):S.t('unsent.refused',{'reason':r});
}
