import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/measure/coordinates.dart';
import 'package:sarcade_app/src/features/measure/measure_controller.dart';
import 'package:sarcade_app/src/features/measure/wmm.dart';

void main(){
  const versailles=LatLng(48.80123,2.13456);

  test('three formats of the spec',(){
    expect(formatDd(versailles),'48,80123 N · 2,13456 E');
    expect(formatDm(versailles),'48°48,074′ N · 002°08,074′ E');
    expect(formatQth(versailles),'JN18BT');
    expect(formatQth(versailles,length:8).length,8);
    expect(formatDd(const LatLng(-33.9,-70.6)),'33,90000 S · 70,60000 O');
  });

  test('coordinates typed in any format',(){
    for(final text in ['48.80123, 2.13456','48,80123 N · 2,13456 E','48°48,074′ N 002°08,074′ E','48 48.074 N 2 08.074 E']){
      final p=parseCoordinates(text);
      expect(p,isNotNull,reason:text);
      expect(p!.latitude,closeTo(48.80123,0.0001),reason:text);
      expect(p.longitude,closeTo(2.13456,0.0001),reason:text);
    }
    final qth=parseCoordinates('jn18bt')!;
    expect(formatQth(qth),'JN18BT');
    expect(parseCoordinates('hello'),isNull);
    expect(parseCoordinates('95.0, 2.0'),isNull);
  });

  test('WMM 2025 declination matches the NOAA reference implementation',(){
    final date=DateTime.utc(2026,10,10);
    expect(magneticDeclination(48.80,2.13,date),closeTo(2.0241,0.001));
    expect(magneticDeclination(-33.9,151.2,date),closeTo(12.8362,0.001));
    expect(magneticDeclination(40.7,-74,date),closeTo(-12.4641,0.001));
    expect(decimalYear(DateTime.utc(2026,7,2,12)),closeTo(2026.5,0.002));
  });

  test('compass heading of a phone lying flat',(){
    // Flat, top of the phone towards magnetic north: field along +y (and down).
    expect(compassHeading([0,0,9.8],[0,20,-40]),closeTo(0,0.5));
    // Top towards east: north is on the left (-x).
    expect(compassHeading([0,0,9.8],[-20,0,-40]),closeTo(90,0.5));
  });
}
