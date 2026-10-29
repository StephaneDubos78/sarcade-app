import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/orders/move_orders.dart';

void main() {
  MoveOrder order(String status)=>MoveOrder({'id':'o','target_id':'TEL-02','created_by':'PCO','status':status,
    'destination':{'lat':48.78,'lon':2.02,'label':'Point haut'},'note':''});

  test('an accepted order is reached within 50 m only', () {
    expect(moveOrderReached(order('accepted'),const LatLng(48.7802,2.02)),isTrue);
    expect(moveOrderReached(order('accepted'),const LatLng(48.79,2.02)),isFalse);
    expect(moveOrderReached(order('sent'),const LatLng(48.78,2.02)),isFalse);
  });

  test('open orders are the sent and accepted ones', () {
    expect(order('sent').open,isTrue);
    expect(order('accepted').open,isTrue);
    for(final s in ['refused','arrived','cancelled']){expect(order(s).open,isFalse);}
    expect(order('sent').label,'Point haut');
  });
}
