import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/basemaps/basemap_models.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';

void main(){
  test('forecast and vigilance from the server answer',(){
    final r=WeatherReport.fromJson({'stale':false,'vigilance':{'department':'78','color_id':3,'phenomena':['orages']},
      'forecast':{'provider':'meteofrance','provider_label':'Météo-France (AROME, ARPEGE)','fetched_at':'2026-10-10T06:00:00Z','lat':48.8,'lon':2.1,
        'hourly':[{'time':'2026-10-10T06:00:00Z','temperature_c':9.5,'gust_kmh':55,'weather_code':95,'wind_direction_deg':240},
                  {'time':'2026-10-10T07:00:00Z','temperature_c':10}],
        'daily':[{'date':'2026-10-10','sunrise':'2026-10-10T06:05:00Z','sunset':'2026-10-10T17:10:00Z'}]}});
    expect(r.hours.length,2);
    expect(r.vigilance!.isAlert,isTrue);
    expect(r.provider,'Météo-France (AROME, ARPEGE)');
    expect(r.upcoming(DateTime.utc(2026,10,10,6,30)).length,2);
    expect(r.upcoming(DateTime.utc(2026,10,10,7,30)).length,1);
    expect(weatherKey(r.hours.first.weatherCode),'storm');
    expect(windDirection(240),'SO');
    expect(WeatherReport.fromJson({'forecast':null,'stale':true}).isEmpty,isTrue);
  });

  test('sun times computed offline (Versailles, 10 October)',(){
    final s=sunTimes(DateTime.utc(2026,10,10),48.80,2.13);
    // About 06:05 and 17:10 UTC.
    expect(s.sunrise!.hour,6);
    expect(s.sunset!.hour,17);
  });

  test('base map: operator choice, event default, OpenStreetMap',(){
    final catalog=[...builtInBasemaps,const Basemap(id:'carto-78',name:'Carte 78',attribution:'ADRASEC 78',hasOfflinePackage:true,custom:true)];
    expect(pickBasemap(catalog).id,'osm');
    expect(pickBasemap(catalog,eventDefault:'ign-plan').id,'ign-plan');
    expect(pickBasemap(catalog,operatorChoice:'topo',eventDefault:'ign-plan').id,'topo');
    expect(pickBasemap(catalog,operatorChoice:'unknown').id,'osm');
    final local=catalog.last;
    expect(local.tileUrl('http://192.168.1.20:8000',preferOffline:false),'http://192.168.1.20:8000/api/v0.1/basemaps/carto-78/tiles/{z}/{x}/{y}');
    expect(builtInBasemaps[2].url,contains('PLANIGNV2'));
    expect(builtInBasemaps[2].url,contains('TILEMATRIX={z}&TILEROW={y}&TILECOL={x}'));
    expect(mergeCatalog([]).length,4);
  });
}
