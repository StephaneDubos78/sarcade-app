import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/measure/coordinates.dart';
import 'package:sarcade_app/src/features/measure/lambert.dart';

// Reference values: pyproj (EPSG:2154 and EPSG:27572 with the IGN
// three-parameter shift), DFCI lettering of ol-ext.
const List<(double,double,double?,double?,double,double,String)> refs=[
  (48.8530,2.3499,652296.973,6861636.359,600983.496,2428295.309,'GL02A4.4'),
  (48.80123,2.13456,636433.222,6856031.927,585157.104,2422554.315,'FL82C1.5'),
  (43.2965,5.3698,892390.222,6247035.257,846499.547,1815214.128,'KD40D7.1'),
  (46.5,3.0,700000.0,6600000.0,650923.300,2166874.680,'GG46F3.5'),
  (44.0,6.5,null,null,934129.2,1897577.9,'LD28H8.1'),
  (42.7,9.45,null,null,1183438.4,1770472.4,'NC86B5.3'),
];

double distanceM(LatLng a,LatLng b)=>const Distance().as(LengthUnit.Meter,a,b);

void main(){
  test('Lambert 93 against pyproj, millimetric, and back',(){
    for(final r in refs){
      if(r.$3==null)continue;
      final l=toLambert93(LatLng(r.$1,r.$2));
      expect(l.x,closeTo(r.$3!,0.01));
      expect(l.y,closeTo(r.$4!,0.01));
      final back=fromLambert93(l.x,l.y);
      expect(back.latitude,closeTo(r.$1,1e-8));
      expect(back.longitude,closeTo(r.$2,1e-8));
    }
  });

  test('Lambert II étendu (NTF, three-parameter shift) and back',(){
    for(final r in refs){
      final l=toLambert2e(LatLng(r.$1,r.$2));
      expect(l.x,closeTo(r.$5,0.2));
      expect(l.y,closeTo(r.$6,0.2));
      expect(distanceM(fromLambert2e(l.x,l.y),LatLng(r.$1,r.$2)),lessThan(0.05));
    }
  });

  test('DFCI index of the reference points, levels, and centre back',(){
    for(final r in refs){
      final p=LatLng(r.$1,r.$2);
      expect(formatDfci(p),r.$7);
      expect(formatDfci(p,level:0),r.$7.substring(0,2));
      expect(formatDfci(p,level:2),r.$7.substring(0,6));
      expect(distanceM(parseDfci(r.$7)!,p),lessThan(600));
    }
    expect(parseDfci('FL 82 C1.5'),isNotNull);
    expect(parseDfci('IL82C1'),isNull);
    expect(formatDfci(const LatLng(40.7,-74.0)),isNull);
  });

  test('Lambert 93 text, typed with or without separators',(){
    const p=LatLng(48.80123,2.13456);
    expect(formatLambert93(p),'X 636 433 · Y 6 856 031');
    for(final t in ['X 636433 Y 6856031','636433 6856031','L93 636 433 / 6 856 031',formatLambert93(p)!]){
      expect(distanceM(parseLambert93(t)!,p),lessThan(2),reason:t);
      expect(distanceM(parseCoordinates(t)!,p),lessThan(2),reason:t);
    }
    expect(parseLambert93('48.8 2.1'),isNull);
    expect(formatLambert93(const LatLng(-33.8,151.2)),isNull);
    expect(parseCoordinates('FL82C1.5'),isNotNull);
  });
}
