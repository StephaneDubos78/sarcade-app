import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/recipient.dart';
void main(){
 test('recipient protocol ids are explicit',(){
  expect(const SarcadeRecipient(id:'alpha',label:'Alpha',type:'team').protocolId,'team:alpha');
  expect(const SarcadeRecipient(id:'u42',label:'Agent',type:'user').protocolId,'user:u42');
 });
}
