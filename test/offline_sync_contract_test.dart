import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/offline/sync_operation.dart';
void main(){
 test('offline operation keeps stable ids',(){
  final op=SyncOperation(operationId:'op-1',eventId:'evt',objectId:'msg-1',objectType:'message',action:'create',clientTime:DateTime.utc(2026,10,2),payload:{'body':'RAS'});
  final j=op.toJson();
  expect(j['operation_id'],'op-1'); expect(j['object_id'],'msg-1'); expect(j['object_type'],'message');
 });
}
