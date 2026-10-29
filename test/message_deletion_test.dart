import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/message_deletion.dart';
import 'package:sarcade_app/src/features/settings/quick_messages_editor.dart';
import 'package:sarcade_app/src/models/message.dart';

void main(){
  final sent=DateTime.utc(2026,10,29,10);
  SarcadeMessage msg({String sender='TEL-01',bool deleted=false})=>SarcadeMessage(id:'m1',eventId:'e1',senderId:sender,recipientIds:const [],priority:'routine',body:'Véhicule repéré',createdAt:sent,deleted:deleted);

  test('author for 2 days, PCO always',(){
    expect(canDeleteForEveryone(msg(),'TEL-01',pco:false,now:sent.add(const Duration(days:1))),isTrue);
    expect(canDeleteForEveryone(msg(),'TEL-01',pco:false,now:sent.add(const Duration(days:2,minutes:1))),isFalse);
    expect(canDeleteForEveryone(msg(),'TEL-02',pco:false,now:sent),isFalse);
    expect(canDeleteForEveryone(msg(),'PCO',pco:true,now:sent.add(const Duration(days:30))),isTrue);
    expect(canDeleteForEveryone(msg(deleted:true),'PCO',pco:true,now:sent),isFalse);
  });

  test('a deleted message never comes back with its text',(){
    final m=msg().toJson();
    final del=deletedMessage(m,by:'PCO',byPco:true,at:sent);
    expect(SarcadeMessage.fromJson(del).deleted,isTrue);
    expect(SarcadeMessage.fromJson(del).deletedByPco,isTrue);
    expect(del['body'],'');
    // Realtime deletion carries only the id: merged onto the known message.
    final merged=mergeCachedMessage(m,{'id':'m1','event_id':'e1','deleted':true,'deleted_by':'TEL-01'})!;
    expect(merged['body'],''); expect(merged['sender_id'],'TEL-01');
    // The creation brought again by the feed keeps it deleted.
    final again=mergeCachedMessage(merged,m)!;
    expect(again['body'],''); expect(again['deleted'],isTrue);
    expect(mergeCachedMessage(null,{'id':'m1','deleted':true}),isNull);
    expect(mergeCachedMessage(null,m),m);
  });

  test('hidden for me',(){
    expect(parseHidden(formatHidden({'a','b'})),{'a','b'});
    expect(formatHidden({}),isNull);
    expect(parseHidden(null),isEmpty);
  });

  test('predefined messages: cleaned, 20 at most, defaults offered',(){
    expect(cleanQuickMessages([' En place ','','  ','Retour PCO']),['En place','Retour PCO']);
    expect(cleanQuickMessages(List.filled(30,'x')).length,20);
    expect(defaultQuickMessages(),isNotEmpty);
  });
}
