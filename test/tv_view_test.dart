import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/tv/tv_view.dart';

void main() {
  test('view sent to a TV keeps only an https base map', () {
    final j=tvViewJson((center:const LatLng(48.8,2.1),zoom:14.3333,basemapId:'ign',tileUrl:'https://data.geopf.fr/{z}/{x}/{y}',attribution:'IGN'));
    expect(j['zoom'],14.33);
    expect(j['tile_url'],'https://data.geopf.fr/{z}/{x}/{y}');
    final local=tvViewJson((center:const LatLng(48.8,2.1),zoom:12,basemapId:'pkg',tileUrl:'http://192.168.0.110:8000/tiles/{z}/{x}/{y}',attribution:''));
    expect(local.containsKey('tile_url'),isFalse);
  });

  test('step 2: layers, opacities and messages panel sent with the view', () {
    final j=tvViewJson((center:const LatLng(48.8,2.1),zoom:12,basemapId:'osm',tileUrl:null,attribution:''),
      options:(layers:{'operators':true,'bearings':false},opacity:{'ops':0.333,'draw':0.05},messages:false));
    expect(j['layers'],{'operators':true,'bearings':false});
    expect(j['opacity'],{'ops':0.33,'draw':0.1});
    expect(j['messages'],isFalse);
  });
}
