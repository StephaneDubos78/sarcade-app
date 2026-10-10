import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/photo_attachment.dart';
import 'package:sarcade_app/src/models/message.dart';

Map<String,dynamic> _op(String type,{List<Map<String,dynamic>>? attachments})=>{
  'operation_id':'op-$type','object_type':type,'object_id':'o1',
  'payload':<dynamic,dynamic>{'id':'o1','attachments':?attachments},
};

void main(){
 test('message with photo round trips through the protocol',(){
  final m=SarcadeMessage(id:'m1',eventId:'e1',senderId:'u1',recipientIds:const [],priority:'urgent',body:'Véhicule repéré',createdAt:DateTime.utc(2026,10,10,12),
    attachments:const [SarcadeAttachment(fileId:'f1',name:'photo.jpg',mimeType:'image/jpeg',sizeBytes:1234)]);
  final j=m.toJson();
  expect((j['attachments'] as List).single['file_id'],'f1');
  final back=SarcadeMessage.fromJson(j);
  expect(back.attachments.single.isImage,isTrue);
  expect(back.attachments.single.sizeBytes,1234);
 });
 test('message without attachments keeps the V0.1 payload',(){
  final m=SarcadeMessage.fromJson({'id':'m1','event_id':'e1','sender_id':'u1','recipient_ids':[],'priority':'routine','body':'Texte','created_at':'2026-10-02T00:00:00Z'});
  expect(m.attachments,isEmpty);
  expect(m.toJson().containsKey('attachments'),isFalse);
 });
 test('attachments stored by Hive (untyped maps) are read',(){
  final m=SarcadeMessage.fromJson({'id':'m1','event_id':'e1','sender_id':'u1','body':'x','created_at':'2026-10-02T00:00:00Z',
    'attachments':[<dynamic,dynamic>{'file_id':'f1','mime_type':'image/png'},'junk']});
  expect(m.attachments.single.name,'photo.jpg');
  expect(m.attachments.single.mimeType,'image/png');
 });
 test('mime type falls back on the file name',(){
  expect(photoMimeType('image/PNG','x'),'image/png');
  expect(photoMimeType(null,'IMG_1.HEIC'),'image/heic');
  expect(photoMimeType('application/octet-stream','a.webp'),'image/webp');
  expect(photoMimeType(null,'capture'),'image/jpeg');
 });
 test('photo name is sortable and typed',(){
  final n=photoFileName(DateTime(2026,10,10,9,5,7),'image/jpeg');
  expect(n,'photo-20261010-090507.jpg');
  expect(photoFileName(DateTime(2026,1,2),'image/png'),endsWith('.png'));
 });
 test('a message waits for its photos, other operations go through',(){
  final ops=[
    _op('position'),
    _op('message',attachments:[{'file_id':'f1'}]),
    _op('message',attachments:[{'file_id':'f2'}]),
    _op('message'),
    _op('ack'),
  ];
  final ready=readyOperations(ops,{'f1'});
  expect(ready.length,4);
  expect(ready.any((o)=>(o['payload'] as Map)['attachments']?.first['file_id']=='f1'),isFalse);
  expect(readyOperations(ops,const {}),same(ops));
 });
}
