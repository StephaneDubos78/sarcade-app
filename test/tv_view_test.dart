import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/tv/tv_nearby.dart';
import 'package:sarcade_app/src/features/tv/tv_view.dart';

void main() {
  test('view sent to a TV keeps only an https base map', () {
    final j=tvViewJson((center:const LatLng(48.8,2.1),zoom:14.3333,basemapId:'ign',tileUrl:'https://data.geopf.fr/{z}/{x}/{y}',attribution:'IGN',basemapName:'Plan IGN'));
    expect(j['zoom'],14.33);
    expect(j['tile_url'],'https://data.geopf.fr/{z}/{x}/{y}');
    final local=tvViewJson((center:const LatLng(48.8,2.1),zoom:12,basemapId:'pkg',tileUrl:'http://192.168.0.110:8000/tiles/{z}/{x}/{y}',attribution:'',basemapName:''));
    expect(local.containsKey('tile_url'),isFalse);
  });

  test('step 2: layers, opacities and messages panel sent with the view', () {
    final j=tvViewJson((center:const LatLng(48.8,2.1),zoom:12,basemapId:'osm',tileUrl:null,attribution:'',basemapName:'OpenStreetMap'),
      options:(layers:{'operators':true,'bearings':false},opacity:{'ops':0.333,'draw':0.05},messages:false));
    expect(j['layers'],{'operators':true,'bearings':false});
    expect(j['opacity'],{'ops':0.33,'draw':0.1});
    expect(j['messages'],isFalse);
  });

  test('lot 4: sender of the view, one opacity per layer, layers summarised', () {
    final v=(center:const LatLng(48.8,2.1),zoom:12.0,basemapId:'osm',tileUrl:null,attribution:'',basemapName:'OpenStreetMap');
    expect(tvViewJson(v,from:' PCO-Web ')['from'],'PCO-Web');
    expect(tvViewJson(v,from:'').containsKey('from'),isFalse);
    expect(tvOpacityKeys,['ops','aprs','draw','brg','high','relay']);
    expect(tvShownLayers({'relays':true,'operators':true,'offline':true,'aprs':false}),['operators','relays']);
  });

  test('lot 4: readable date, old screens hidden, nearby codes offered once', () {
    final t=DateTime(2026,10,30,14,16).millisecondsSinceEpoch/1000;
    expect(tvWhen(t),'30/10 à 14 h 16');
    expect(tvWhen(t,lang:'en'),'30/10 at 14:16');
    expect(tvWhen(null),'');
    final list=[{'id':'a','active':true},{'id':'b','active':false,'revoked':true}];
    expect([for(final d in tvVisibleScreens(list,showOld:false))d['id']],['a']);
    expect(tvVisibleScreens(list,showOld:true).length,2);
    expect(tvCodesToOffer(['AB','CD'],{'AB'}),['CD']);
  });
}
