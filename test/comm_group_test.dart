import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/comm_group.dart';

CommGroup g(String id,{String mode='discussion',List<String> senders=const [],List<String> managers=const ['TEL-01'],
    List<String> members=const [],bool archived=false,String kind='custom'})=>CommGroup(id:id,eventId:'evt',name:id,
  mode:mode,kind:kind,createdBy:'TEL-01',updatedBy:'TEL-01',senders:senders,managers:managers,members:members,
  archived:archived,updatedAt:DateTime.utc(2026,10,10));

void main(){
  test('listen-only groups: senders, managers and the PCO write',(){
    final diffusion=g('diffusion',mode:'listen_only',senders:['PCO'],managers:['PCO']);
    expect(diffusion.canSend('TEL-02'),isFalse);
    expect(diffusion.canSend('PCO-2'),isTrue);
    expect(g('x',mode:'listen_only',senders:['TEL-05']).canSend('TEL-05'),isTrue);
    expect(g('y',archived:true).canSend('PCO'),isFalse);
    expect(g('z').canSend('TEL-09'),isTrue);
  });

  test('managers and the PCO change a group',(){
    expect(g('a').canManage('TEL-01'),isTrue);
    expect(g('a').canManage('TEL-02'),isFalse);
    expect(g('a').canManage('PCO'),isTrue);
  });

  test('round trip and sorting',(){
    final a=g('Logistique',kind:'default'), b=g('Tous',kind:'all'), c=g('Binôme');
    expect(CommGroup.fromJson(a.toJson()).toJson(),a.toJson());
    expect(sortedGroups([c,a,b,g('old',archived:true)]).map((x)=>x.name),['Tous','Logistique','Binôme']);
  });

  test('messages addressed to this terminal',(){
    final groups={'eq1':g('eq1',members:['TEL-01']),'all':g('all')};
    expect(addressedTo([],'TEL-02',groups),isTrue);
    expect(addressedTo(['group:eq1'],'TEL-02',groups),isFalse);
    expect(addressedTo(['group:eq1'],'TEL-01',groups),isTrue);
    expect(addressedTo(['group:all'],'TEL-02',groups),isTrue);
    expect(addressedTo(['group:unknown'],'TEL-02',groups),isTrue);
    expect(addressedTo(['user:TEL-03'],'TEL-02',groups),isFalse);
  });

  test('ids typed in a field',(){
    expect(parseIds('TEL-01, TEL-02;TEL-01  PCO'),['TEL-01','TEL-02','PCO']);
  });
}
