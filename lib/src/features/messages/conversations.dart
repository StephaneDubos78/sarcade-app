/// Conversations of the messages screen (« Messages façon WhatsApp », 28 Oct
/// 2026): the channel « Tous » (general broadcast), the other channels, and
/// the direct chats with an operator. No « all messages » view any more: the
/// recipient is the conversation that is open.
library;

import '../../models/comm_group.dart';
import '../../models/message.dart';

const allKey='all';
String groupKey(String id)=>'g:$id';
String directKey(String peer)=>'u:$peer';
String? peerOf(String key)=>key.startsWith('u:')?key.substring(2):null;
String? groupOf(String key)=>key.startsWith('g:')?key.substring(2):null;

bool _toMe(List<String> r,String me)=>r.contains(me)||r.contains('user:$me');
String _bare(String r)=>r.replaceFirst(RegExp(r'^(user|team):'),'');

/// Conversation of a message seen from [me]: broadcast and the « Tous »
/// channel together, a channel, or a direct chat (the other person).
String conversationOf(SarcadeMessage m,String me,Map<String,CommGroup> groups){
  final r=m.recipientIds;
  if(r.isEmpty)return allKey;
  final g=r.firstWhere((x)=>x.startsWith('group:'),orElse:()=>'');
  if(g.isNotEmpty){
    final id=g.substring(6);
    return groups[id]?.kind=='all'?allKey:groupKey(id);
  }
  if(m.senderId==me)return directKey(_bare(r.first));
  if(_toMe(r,me))return directKey(m.senderId);
  return directKey(_bare(r.first));
}

/// Recipients of a message written in a conversation: none for « Tous »
/// (general broadcast), the channel, or the operator.
List<String> recipientsFor(String key,Map<String,CommGroup> groups){
  final g=groupOf(key);
  if(g!=null)return [groups[g]?.recipientId??'group:$g'];
  final p=peerOf(key);
  if(p!=null)return ['user:$p'];
  return const [];
}

/// Direct chats known from the messages, most recent first.
List<String> directPeers(Iterable<SarcadeMessage> messages,String me,Map<String,CommGroup> groups){
  final last=<String,DateTime>{};
  for(final m in messages){
    final p=peerOf(conversationOf(m,me,groups));
    if(p==null||p==me)continue;
    final t=last[p];
    if(t==null||m.createdAt.isAfter(t))last[p]=m.createdAt;
  }
  return last.keys.toList()..sort((a,b)=>last[b]!.compareTo(last[a]!));
}

/// Summary of the acknowledgements of a message sent to several people:
/// how many read it and how many received it (« ✓✓ lu par 6 · reçu par 8 »).
({int read,int received}) ackSummary(String senderId,List<SarcadeAck> acks){
  final read=<String>{}, received=<String>{};
  for(final a in acks){
    if(a.actorId==senderId)continue;
    received.add(a.actorId);
    if(a.status=='read'||a.status=='accepted'||a.status=='rejected')read.add(a.actorId);
  }
  return (read:read.length,received:received.length);
}

/// Colour of an author's name in a bubble, stable for the person.
int authorColor(String id){
  const palette=[0xFFE53935,0xFFFB8C00,0xFF43A047,0xFF1E88E5,0xFF8E24AA,0xFF00897B,0xFFD81B60,0xFF6D4C41,0xFF3949AB,0xFF7CB342];
  var h=0; for(final c in id.codeUnits){h=(h*31+c)&0x7FFFFFFF;}
  return palette[h%palette.length];
}

/// Date separator of the chat (« Aujourd'hui », « Hier », « 27/10/2026 »):
/// null for the same day as the message before.
String dayKey(DateTime t){final l=t.toLocal();return '${l.year}-${l.month}-${l.day}';}
String dayLabel(DateTime t,DateTime now,{required String today,required String yesterday}){
  final l=t.toLocal(), n=now.toLocal();
  final d=DateTime(l.year,l.month,l.day), td=DateTime(n.year,n.month,n.day);
  final diff=td.difference(d).inDays;
  if(diff==0)return today;
  if(diff==1)return yesterday;
  String two(int v)=>v.toString().padLeft(2,'0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
