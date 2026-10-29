import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/sos_alert.dart';
import 'package:sarcade_app/src/models/message.dart';

SarcadeMessage _m(String id,String who,String body,int minute,{String priority='immediate',List<String> to=const []})=>
  SarcadeMessage(id:id,eventId:'e',senderId:who,recipientIds:to,priority:priority,body:body,createdAt:DateTime.utc(2026,10,29,20,minute));

void main(){
  test('distress open until its end of distress, same sender only',(){
    final sos=_m('1','TEL-01','🆘 DÉTRESSE — TEL-01 — position x',0);
    expect(openDistress([sos],'ME').keys,['TEL-01']);
    expect(openDistress([sos,_m('2','TEL-01','Fin de détresse — TEL-01',1,priority:'urgent')],'ME'),isEmpty);
    expect(openDistress([sos,_m('2','TEL-02','Fin de détresse — TEL-02',1,priority:'urgent')],'ME').keys,['TEL-01']);
    expect(openDistress([sos],'TEL-01'),isEmpty);
    expect(openDistress([_m('3','A','🆘 x',0,to:['user:B'])],'ME'),isEmpty);
  });

  test('mute holds until a new distress arrives',(){
    final a=_m('1','TEL-01','🆘 a',0), b=_m('2','TEL-02','🆘 b',1);
    expect(sosMuted([a],null),isFalse);
    final key=sosMuteKey([a]);
    expect(sosMuted([a],key),isTrue);
    expect(sosMuted([a,b],key),isFalse);
  });
}
