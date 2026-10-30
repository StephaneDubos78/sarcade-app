import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/car/car_context.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/notification_actions.dart';
import 'package:sarcade_app/src/services/notification_keys.dart';

SarcadeMessage _m(String id,{String sender='F4AAA',String body='Bonjour',String priority='routine',
    List<String> to=const ['me'],int minute=0,String event='ev1',bool deleted=false})=>
  SarcadeMessage(id:id,eventId:event,senderId:sender,recipientIds:to,priority:priority,body:body,
    createdAt:DateTime.utc(2026,10,30,18,minute),deleted:deleted);

void main(){
  test('context: complete only, address without the final slash',(){
    final c=CarContext.fromJson({'server_url':'https://sarcade.example.org/','event_id':'ev1','device_id':'F4JPO'});
    expect(c,isNotNull);
    expect(c!.base,'https://sarcade.example.org');
    expect(CarContext.fromJson(c.toJson())!.deviceId,'F4JPO');
    expect(CarContext.fromJson({'server_url':'https://x','event_id':'','device_id':'d'}),isNull);
    expect(CarContext.fromJson('damaged'),isNull);
    expect(CarContext.fromJson(null),isNull);
  });

  test('answer from a notification: the acknowledgement queued later, same identifier',(){
    final a=PendingAnswer(id:'ack-1',eventId:'ev1',messageId:'m1',deviceId:'F4JPO',status:'read',
      time:DateTime.utc(2026,10,30,18,5));
    final op=answerOperation(a,operationId:'op-1').toJson();
    expect(op['object_type'],'ack');
    expect(op['action'],'create');
    expect(op['object_id'],'ack-1');
    expect(op['event_id'],'ev1');
    expect(op['payload'],a.toAck());
  });

  test('server answer: accepted, duplicate or conflict means delivered',(){
    expect(operationDelivered({'status':'accepted'}),isTrue);
    expect(operationDelivered({'status':'duplicate'}),isTrue);
    expect(operationDelivered({'status':'conflict'}),isTrue);
    expect(operationDelivered({'status':'rejected'}),isFalse);
    expect(operationDelivered({'status':'retry'}),isFalse);
    expect(operationDelivered(null),isFalse);
  });

  test('wake-up: the message of the tag, never one of mine nor a deleted one',(){
    final list=[_m('m1'),_m('m2',minute:1),_m('m3',sender:'me',minute:2),_m('m4',deleted:true,minute:3)];
    expect(wokenMessage({'event_id':'ev1','tag':'m2'},list,deviceId:'me')!.id,'m2');
    expect(wokenMessage({'event_id':'ev1','tag':'m3'},list,deviceId:'me'),isNull);
    expect(wokenMessage({'event_id':'ev1','tag':'m4'},list,deviceId:'me'),isNull);
    expect(wokenMessage({'event_id':'ev2','tag':'m1'},list,deviceId:'me'),isNull);
    expect(wokenMessage({'event_id':'ev1'},list,deviceId:'me'),isNull);
  });

  test('wake-up of a distress: the latest message of the sender (distress or its end)',(){
    final sos=_m('s1',sender:'F4BBB',body:'🆘 DÉTRESSE — F4BBB — position inconnue',priority:'immediate',to:const []);
    final end=_m('s2',sender:'F4BBB',body:'Fin de détresse — F4BBB',to:const [],minute:4);
    final tag=sosKey('ev1','F4BBB');
    expect(messageNotificationKey(sos),tag);
    expect(wokenMessage({'event_id':'ev1','tag':tag},[sos],deviceId:'me')!.id,'s1');
    expect(wokenMessage({'event_id':'ev1','tag':tag},[end,sos],deviceId:'me')!.id,'s2');
  });
}
