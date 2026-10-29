import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

void main() {
  test('opacity of a drawn object is kept and sent only below 100 %', () {
    final f=MapFeature(id:'z',eventId:'e',kind:FeatureKind.zone,points:const [LatLng(48.7,2.0),LatLng(48.8,2.1),LatLng(48.7,2.2)],
      color:0xFFE53935,strokeWidth:4,updatedAt:DateTime.utc(2026,10,29));
    expect(f.opacity,1);
    expect(f.toJson().containsKey('opacity'),isFalse);
    final half=f.copyWith(opacity:0.5);
    expect(half.toJson()['opacity'],0.5);
    expect(MapFeature.fromJson(half.toJson()).opacity,0.5);
    expect(MapFeature.fromJson({...f.toJson(),'opacity':0}).opacity,0.1);
    expect(half.toGeoJson()['properties']['fill-opacity'],0.5);
  });
}
