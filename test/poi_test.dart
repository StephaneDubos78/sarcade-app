import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/measure/coordinates.dart';
import 'package:sarcade_app/src/features/poi/poi_sheet.dart';
import 'package:sarcade_app/src/models/poi.dart';

void main(){
  SarcadePoi poi({String? by='TEL-02',int? color})=>SarcadePoi(id:'p1',eventId:'e1',kind:'designated',lat:48.82,lon:1.91,
    createdAt:DateTime.utc(2026,10,29,18),label:'Point haut',createdBy:by,color:color);

  test('the pin is never the red of the beacons',(){
    expect(isReservedRed(0xFFE53935),isTrue);
    expect(isReservedRed(0xFF1E88E5),isFalse);
    expect(poiColorFor(0xFFE53935),poiFallbackColor);
    expect(poiColor(poi(color:0xFF43A047)),0xFF43A047);
    expect(isReservedRed(poiColor(poi(color:0xFFFF0000))),isFalse);
    expect(isReservedRed(poiColor(poi())),isFalse);
  });

  test('a new point carries its author and colour',(){
    final j=newPoiJson(id:'p',eventId:'e1',at:const LatLng(48.8,2.1),label:'Gué',actor:'TEL-02',drawColor:0xFF43A047);
    final p=SarcadePoi.fromJson(j);
    expect(p.createdBy,'TEL-02'); expect(p.color,0xFF43A047); expect(p.label,'Gué');
    expect(SarcadePoi.fromJson(p.toJson()).color,0xFF43A047);
  });

  test('rights: the author or the PCO',(){
    expect(canEditPoi(poi(),'TEL-02'),isTrue);
    expect(canEditPoi(poi(),'TEL-03'),isFalse);
    expect(canEditPoi(poi(),'PCO'),isTrue);
    expect(canEditPoi(poi(by:null),'TEL-02'),isFalse);
  });

  test('old points without author still read, deleted flag read',(){
    final p=SarcadePoi.fromJson({'id':'x','event_id':'e1','kind':'designated','lat':1,'lon':2,'created_at':'2026-10-01T00:00:00Z'});
    expect(p.createdBy,isNull); expect(p.deleted,isFalse);
    expect(SarcadePoi.fromJson({...p.toJson(),'deleted':true}).deleted,isTrue);
  });

  test('message text has the name and the coordinates',(){
    final m=poiMessage(poi(),CoordFormat.dd);
    expect(m,contains('Point haut')); expect(m,contains('48,82'));
  });
}
