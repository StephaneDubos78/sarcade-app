import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/measure/coordinates.dart';
import 'package:sarcade_app/src/features/measure/measure_controller.dart';

// Reference values: pyproj (EPSG:326xx/327xx) and the mgrs package.
const refs=[
  (48.80123,2.13456,31,436448.343,5405721.000,'31UDQ3644805721'),
  (48.85837,2.29448,31,448250.503,5411951.589,'31UDQ4825011951'),
  (-33.8688,151.2093,56,334368.634,6250948.345,'56HLH3436850948'),
  (40.7128,-74.006,18,583959.372,4507350.998,'18TWL8395907350'),
  (60.0,5.5,32,304838.827,6656575.859,'32VLM0483856575'),
  (78.2232,15.6267,33,514278.715,8683355.469,'33XWG1427883355'),
  (0.0001,9.0,32,500000.000,11.053,'32NNF0000000011'),
  (-0.5,-78.5,17,778265.778,9944681.960,'17MQV7826544681'),
  (83.9,-30.0,26,464424.320,9317856.466,'26XMU6442417856'),
  (-79.9,100.0,47,519576.611,1129407.483,'47CNM1957629407'),
  (56.5,3.5,32,161622.346,6275290.406,'32VJH6162275290'),
  (71.99,10.0,32,534507.532,7988103.476,'32WNE3450788103'),
  (48.5,4.99,31,647001.413,5373787.897,'31UFP4700173787'),
];

String spaced(String m,int digits){
  final z=RegExp(r'^\d+').firstMatch(m)![0]!;
  final rest=m.substring(z.length);
  final e=rest.substring(3,8).substring(0,digits), n=rest.substring(8,13).substring(0,digits);
  return '$z${rest[0]} ${rest.substring(1,3)} $e $n';
}

void main(){
  test('UTM within a few centimetres of pyproj, with the Norway and Svalbard zones',(){
    for(final r in refs){
      final u=toUtm(LatLng(r.$1,r.$2))!;
      expect(u.zone,r.$3,reason:'${r.$1},${r.$2}');
      expect(u.easting,closeTo(r.$4,0.05),reason:'E ${r.$1},${r.$2}');
      expect(u.northing,closeTo(r.$5,0.05),reason:'N ${r.$1},${r.$2}');
    }
  });

  test('UTM back to latitude and longitude',(){
    for(final r in refs){
      final p=fromUtm(r.$3,r.$1>=0,r.$4,r.$5)!;
      expect(p.latitude,closeTo(r.$1,1e-6));
      expect(p.longitude,closeTo(r.$2,1e-6));
    }
  });

  test('MGRS at 10 m and 1 m like the mgrs package',(){
    for(final r in refs){
      final p=LatLng(r.$1,r.$2);
      expect(formatMgrs(p),spaced(r.$6,4),reason:'${r.$1},${r.$2}');
      if(r.$1!=48.80123)expect(formatMgrs(p,digits:5),spaced(r.$6,5),reason:'${r.$1},${r.$2}');
    }
  });

  test('MGRS typed in any spacing gives the centre of the square',(){
    for(final r in refs){
      final p=parseMgrs(r.$6)!;
      expect(distanceM(p,LatLng(r.$1,r.$2)),lessThan(1.5),reason:r.$6);
      final p10=parseMgrs(spaced(r.$6,4))!;
      expect(distanceM(p10,LatLng(r.$1,r.$2)),lessThan(15),reason:r.$6);
    }
    expect(parseMgrs('31U DQ 36448 05721'),isNotNull);
    expect(parseMgrs('31UDQ123'),isNull);
    expect(parseMgrs('31UIQ1234'),isNull);
  });

  test('UTM typed, band checked',(){
    final p=parseUtm('31U 436448 5405721')!;
    expect(p.latitude,closeTo(48.80123,1e-4));
    expect(parseUtm('31 U 436448E 5405721N'),isNotNull);
    expect(parseUtm('31C 436448 5405721'),isNull);
  });

  test('polar areas have no UTM nor MGRS',(){
    expect(formatUtm(const LatLng(85,10)),isNull);
    expect(formatCoordinates(const LatLng(-85,10),CoordFormat.mgrs),'—');
  });

  test('degrees, minutes, seconds both ways',(){
    const p=LatLng(48.80123,2.13456);
    expect(formatDms(p),'48°48′04,4″ N · 002°08′04,4″ E');
    final back=parseCoordinates('48°48′04,4″ N 2°08′04,4″ E')!;
    expect(back.latitude,closeTo(48.80123,2e-5));
    expect(back.longitude,closeTo(2.13456,2e-5));
    expect(parseCoordinates("48 48 4.4 N, 2 8 4.4 E"),isNotNull);
  });

  test('every format typed is understood',(){
    const p=LatLng(48.80123,2.13456);
    for(final f in CoordFormat.values){
      final text=formatCoordinates(p,f,mgrsDigits:5);
      final back=parseCoordinates(text);
      expect(back,isNotNull,reason:text);
      final tolerance=f==CoordFormat.qth?3000.0:5.0;
      expect(distanceM(back!,p),lessThan(tolerance),reason:text);
    }
  });

  test('manual declination typed east or west, WMM warning after 2030',(){
    expect(parseDeclination('2,5'),2.5);
    expect(parseDeclination('1.2 O'),-1.2);
    expect(parseDeclination('1.2W'),-1.2);
    expect(parseDeclination('-3 E'),3);
    expect(parseDeclination('2,5°E'),2.5);
    expect(parseDeclination('abc'),isNull);
    expect(parseDeclination('95'),isNull);
    expect(formatDeclination(-1.24),'1,2° O');
    expect(formatDeclination(2,decimal:'.',west:'W'),'2.0° E');
    expect(MeasureController.wmmExpired(DateTime.utc(2029,12,31)),isFalse);
    expect(MeasureController.wmmExpired(DateTime.utc(2030,1,1,1)),isTrue);
  });

  test('card formats: main first, base formats, the rest behind « More formats »',(){
    expect(cardFormats(CoordFormat.dd).shown,[CoordFormat.dd,CoordFormat.dm,CoordFormat.qth]);
    expect(cardFormats(CoordFormat.dd).more,[CoordFormat.dms,CoordFormat.utm,CoordFormat.mgrs]);
    expect(cardFormats(CoordFormat.mgrs).shown,[CoordFormat.mgrs,CoordFormat.dd,CoordFormat.dm,CoordFormat.qth]);
    expect(cardFormats(CoordFormat.mgrs).more,[CoordFormat.dms,CoordFormat.utm]);
    expect(coordFormatFrom('utm'),CoordFormat.utm);
    expect(coordFormatFrom('nope'),CoordFormat.dd);
  });
}

double distanceM(LatLng a,LatLng b)=>const Distance().as(LengthUnit.Meter,a,b);
