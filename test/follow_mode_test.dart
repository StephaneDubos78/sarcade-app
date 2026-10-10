import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/navigation/follow_mode.dart';
import 'package:sarcade_app/src/features/routes/route_models.dart';

void main(){
  test('heading: course when moving, compass when stationary, north up without rotation',(){
    expect(followHeading(course:90,speedMs:10,compassTrue:200,rotate:true),90);
    expect(followHeading(course:90,speedMs:0.5,compassTrue:200,rotate:true),200);
    expect(followHeading(course:null,speedMs:10,compassTrue:null,rotate:true),isNull);
    expect(followHeading(course:90,speedMs:10,compassTrue:200,rotate:false),isNull);
  });

  test('map rotation puts the heading at the top',(){
    expect(mapRotationFor(null),0);
    expect(mapRotationFor(90),270);
    expect(mapRotationFor(0),0);
  });

  test('camera updated only when useful',(){
    const a=LatLng(48.8,2.1);
    expect(followNeedsUpdate(center:a,rotation:0),isTrue);
    expect(followNeedsUpdate(lastCenter:a,lastRotation:0,center:a,rotation:1),isFalse);
    expect(followNeedsUpdate(lastCenter:a,lastRotation:359,center:a,rotation:3),isTrue);
    expect(followNeedsUpdate(lastCenter:a,lastRotation:0,center:const LatLng(48.80005,2.1),rotation:0),isTrue);
  });

  test('variants: near-identical and much longer ones dropped, at most two',(){
    final main=Itinerary(geometry:const [LatLng(48.80,2.10),LatLng(48.90,2.10),LatLng(48.90,2.20)],lengthM:18000,durationS:1000);
    final same=Itinerary(geometry:const [LatLng(48.80,2.1001),LatLng(48.90,2.1001),LatLng(48.90,2.20)],lengthM:18000,durationS:1010);
    final east=Itinerary(geometry:const [LatLng(48.80,2.10),LatLng(48.80,2.20),LatLng(48.90,2.20)],lengthM:18500,durationS:1100);
    final diag=Itinerary(geometry:const [LatLng(48.80,2.10),LatLng(48.85,2.15),LatLng(48.90,2.20)],lengthM:13000,durationS:1200);
    final far=Itinerary(geometry:const [LatLng(48.80,2.10),LatLng(48.70,2.15),LatLng(48.90,2.20)],lengthM:40000,durationS:3000);
    expect(sharedShare(same.geometry,main.geometry),greaterThan(0.95));
    expect(sharedShare(east.geometry,main.geometry),lessThan(0.1));
    expect(distinctAlternatives(main,[same,far,east,east,diag]),[east,diag]);
    expect(alternativesFromJson({'alternatives':[{'geometry':[[48.8,2.1],[48.9,2.2]],'length_m':100,'duration_s':10}]}).single.lengthM,100);
  });
}
