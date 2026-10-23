import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/offline/outbox_policy.dart';

const nas='http://192.168.0.110:8000';
const local='http://localhost:8000';

Map<String,dynamic> item(String id,{String type='position',String event='nas1',String? server=nas,
    String time='2026-10-23T10:00:00Z',String? priority,String? objectId,Map<String,dynamic>? payload}){
  final op=<String,dynamic>{
    'operation_id':id,'event_id':event,'object_id':objectId??'obj-$id','object_type':type,'action':'create',
    'client_time':time,
    'payload':payload??{'id':objectId??'obj-$id','event_id':event,'priority':priority,'body':'texte $id','lat':48.8,'lon':2.1},
  };
  if(server!=null)op[localKey]=newLocal(server);
  return op;
}

void main(){
  final now=DateTime.utc(2026,10,23,12);

  test('statuses: accepted, duplicate, conflict leave; rejected and unknown event are set aside; the rest is retried',(){
    expect(outcomeOf('accepted'),SyncOutcome.remove);
    expect(outcomeOf('duplicate'),SyncOutcome.remove);
    expect(outcomeOf('conflict'),SyncOutcome.remove);
    expect(outcomeOf('rejected'),SyncOutcome.setAside);
    expect(outcomeOf('unknown_event'),SyncOutcome.setAside);
    expect(outcomeOf('retry'),SyncOutcome.retry);
    expect(outcomeOf(null),SyncOutcome.retry);
  });

  test('an item set aside never blocks an urgent message placed after it',(){
    final refused=afterFailure(item('a',time:'2026-10-23T09:00:00Z'),now,status:'rejected',setAside:true);
    final urgent=item('b',type:'message',priority:'immediate',time:'2026-10-23T11:00:00Z');
    final batch=nextBatch([refused,item('c'),urgent],nas,'nas1',{});
    expect(batch.map((o)=>o['operation_id']),['b','c']);
  });

  test('incident of 23 October: items of event test1 on the old server stay on the device, nas1 items leave',(){
    final old=[for(var i=0;i<5;i++)item('old$i',event:'test1',server:local)];
    final mine=item('new',type:'message');
    final all=[...old,mine];
    expect(nextBatch(all,nas,'nas1',{}).map((o)=>o['operation_id']),['new']);
    expect(unsentCount(all,nas,'nas1',now),5);
    expect(inFlightCount(all,nas,'nas1',now),1);
    // Back on the old server and event, they leave.
    expect(nextBatch(all,local,'test1',{}).length,5);
    expect(waitingFor(all,local,'test1'),5);
  });

  test('items queued before this version belong to the current server',(){
    final legacy=item('l',server:null);
    expect(belongsTo(legacy,nas,'nas1'),isTrue);
    expect(nextBatch([legacy],nas,'nas1',{}).length,1);
  });

  test('server addresses compared without trailing slash or case',(){
    expect(belongsTo(item('x',server:'HTTP://192.168.0.110:8000/'),nas,'nas1'),isTrue);
  });

  test('priorities: urgent messages, ACK, positions, others; same object keeps its order',(){
    final f1=item('f1',type:'map_feature',objectId:'zone',time:'2026-10-23T10:00:01Z');
    final f2=item('f2',type:'map_feature',objectId:'zone',time:'2026-10-23T10:00:02Z');
    final pos=item('p',time:'2026-10-23T10:00:03Z');
    final ack=item('k',type:'ack',time:'2026-10-23T10:00:04Z');
    final urgent=item('u',type:'message',priority:'urgent',time:'2026-10-23T10:00:05Z');
    final routine=item('r',type:'message',priority:'routine',time:'2026-10-23T10:00:00Z');
    final batch=nextBatch([f2,f1,pos,ack,urgent,routine],nas,'nas1',{});
    expect(batch.map((o)=>o['operation_id']),['u','k','p','r','f1','f2']);
  });

  test('batches are limited in size',(){
    final many=[for(var i=0;i<120;i++)item('m${i.toString().padLeft(3,'0')}')];
    expect(nextBatch(many,nas,'nas1',{}).length,maxBatch);
  });

  test('a message waits for its photo',(){
    final withPhoto=item('ph',type:'message',payload:{'id':'ph','body':'photo','attachments':[{'file_id':'f-1'}]});
    expect(nextBatch([withPhoto],nas,'nas1',{'f-1'}),isEmpty);
    expect(nextBatch([withPhoto],nas,'nas1',{}).length,1);
  });

  test('a transient failure becomes « non envoyé » after 3 tries or 5 minutes, and is still retried',(){
    var op=item('t');
    for(var i=0;i<2;i++){op=afterFailure(op,now,status:'retry');}
    expect(isUnsent(op,nas,'nas1',now),isFalse);
    op=afterFailure(op,now,status:'retry');
    expect(attempts(op),3);
    expect(isUnsent(op,nas,'nas1',now),isTrue);
    expect(nextBatch([op],nas,'nas1',{}).length,1);
    final once=afterFailure(item('t2'),now);
    expect(isUnsent(once,nas,'nas1',now.add(const Duration(minutes:4))),isFalse);
    expect(isUnsent(once,nas,'nas1',now.add(const Duration(minutes:5))),isTrue);
  });

  test('local fields never go to the server',(){
    final op=afterFailure(item('w'),now,reason:'x');
    expect(wire(op).containsKey(localKey),isFalse);
    expect(op.containsKey(localKey),isTrue);
  });

  test('retry resets the counters',(){
    final op=resetForRetry(afterFailure(item('r'),now,status:'rejected',reason:'refusé',setAside:true));
    expect(isSetAside(op),isFalse);
    expect(attempts(op),0);
    expect(reasonOf(op),isNull);
  });

  test('attach to the current event: messages and map objects yes, positions never',(){
    final msg=afterFailure(item('m',type:'message',event:'test1',server:local),now,status:'unknown_event',setAside:true);
    final moved=attachedTo(msg,nas,'nas1');
    expect(moved['event_id'],'nas1');
    expect((moved['payload'] as Map)['event_id'],'nas1');
    expect(itemServer(moved),normalServer(nas));
    expect(isSetAside(moved),isFalse);
    expect(canAttach(item('f',type:'map_feature')),isTrue);
    expect(canAttach(item('p')),isFalse);
    expect(()=>attachedTo(item('p'),nas,'nas1'),throwsArgumentError);
  });

  test('summary lines',(){
    expect(itemSummary(item('m',type:'message')),'texte m');
    expect(itemSummary(item('p')),'48.80000, 2.10000');
  });
}
