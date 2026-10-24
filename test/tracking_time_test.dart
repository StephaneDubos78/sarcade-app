import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/operations/tracking_service.dart';

void main(){
  final now=DateTime.utc(2026,10,23,18,30);
  test('a GPS time dated 1970 is replaced by the current time (Windows)',(){
    expect(fixTime(DateTime.utc(1970,1,21,4,16),now),now);
    expect(fixTime(DateTime.fromMillisecondsSinceEpoch(0,isUtc:true),now),now);
  });
  test('a time far in the future or the past is replaced too',(){
    expect(fixTime(now.add(const Duration(days:3)),now),now);
    expect(fixTime(now.subtract(const Duration(days:2)),now),now);
  });
  test('a normal GPS time is kept, in UTC',(){
    final t=now.subtract(const Duration(seconds:4));
    expect(fixTime(t,now),t);
    expect(fixTime(t.toLocal(),now),t);
  });
}
