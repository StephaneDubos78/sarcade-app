import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/message_reception.dart';

void main(){
  final now=DateTime.utc(2026,10,25,13,40);
  test('first arrival of a recent message notifies',(){
    expect(shouldNotifyMessage(alreadyReceived:false,createdAt:now.subtract(const Duration(seconds:5)),now:now),isTrue);
  });
  test('second arrival (realtime then synchronisation) stays silent',(){
    expect(shouldNotifyMessage(alreadyReceived:true,createdAt:now,now:now),isFalse);
  });
  test('old message caught up stays silent',(){
    expect(shouldNotifyMessage(alreadyReceived:false,createdAt:now.subtract(const Duration(hours:13)),now:now),isFalse);
  });
  test('clock slightly ahead on the sender still notifies',(){
    expect(shouldNotifyMessage(alreadyReceived:false,createdAt:now.add(const Duration(minutes:2)),now:now),isTrue);
  });
}
