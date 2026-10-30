import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/aprs/aprs_models.dart';
import 'package:sarcade_app/src/features/aprs/callsign_links.dart';
import 'package:sarcade_app/src/features/map/point_menu.dart';
import 'package:sarcade_app/src/features/measure/coordinates.dart';
import 'package:sarcade_app/src/features/measure/point_info_page.dart';
import 'package:sarcade_app/src/features/measure/radio_spelling.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart';
import 'package:sarcade_app/src/features/tools/converter_input.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main(){
  setUp(()=>S.setLanguage('fr'));
  tearDown(()=>S.setLanguage('fr'));

  test('radio reading in the NATO alphabet',(){
    expect(radioSpelling('31U DQ'),'trois un Uniform — Delta Québec');
    expect(radioSpelling('JN18',lang:'en'),'Juliett November one eight');
    expect(radioSpelling('48,5 N'),'quatre huit virgule cinq — November');
  });

  test('recognised format of a typed text',(){
    expect(detectFormat('31U DQ 3644 0572'),CoordFormat.mgrs);
    expect(detectFormat('31U 436448 5405721'),CoordFormat.utm);
    expect(detectFormat('JN18bt'),CoordFormat.qth);
    expect(detectFormat('FL82C1.5'),CoordFormat.dfci);
    expect(detectFormat('X 636433 Y 6856031'),CoordFormat.l93);
    expect(detectFormat('48,80123 N 2,13456 E'),CoordFormat.dd);
    expect(detectFormat("48°48,074' N 2°08,074' E"),CoordFormat.dm);
    expect(detectFormat('48°48′04,4″ N · 002°08′04,4″ E'),CoordFormat.dms);
    expect(detectFormat('n’importe quoi'),isNull);
  });

  test('guided fields build a text the parser understands',(){
    final dms=guidedText(CoordFormat.dms,{'latD':'48','latM':'48','latS':'4.4','lonD':'2','lonM':'8','lonS':'4.4'});
    final p=parseCoordinates(dms)!;
    expect(p.latitude,closeTo(48.80122,1e-4));
    expect(parseCoordinates(guidedText(CoordFormat.mgrs,{'gzd':'31u','square':'dq','e':'3644','n':'0572'})),isNotNull);
    expect(parseCoordinates(guidedText(CoordFormat.utm,{'zone':'31','band':'u','e':'436448','n':'5405721'})),isNotNull);
    expect(parseCoordinates(guidedText(CoordFormat.l93,{'x':'636433','y':'6856031'})),isNotNull);
    for(final f in guidedFormats){expect(guidedFieldsOf(f),isNotEmpty);for(final k in guidedFieldsOf(f)){expect(S.t('converter.f.$k'),isNot('converter.f.$k'));}}
  });

  test('history: 10 newest, no duplicate',(){
    var h=<Map<String,dynamic>>[];
    for(var i=0;i<12;i++){h=pushHistory(h,LatLng(48+i/100,2),'P$i');}
    expect(h.length,10);
    expect(h.first['label'],'P11');
    h=pushHistory(h,const LatLng(48.05,2),'again');
    expect(h.length,10);
    expect(h.first['label'],'again');
    expect(h.where((e)=>(e['lat'] as num)==48.05).length,1);
  });

  test('fiche « Infos du point »: blocks and copy all',(){
    const point=LatLng(48.80123,2.13456);
    final place={'commune':{'name':'Plaisir','code':'78490'},'department':'78','label':'800 m au nord de Plaisir',
      'road':{'label':'Rue de la Gare 78370 Plaisir'},'altitude_m':112.4};
    final lines=pointInfoLines(point:point,place:place,from:const LatLng(48.79,2.13),now:DateTime.utc(2026,10,30));
    final m={for(final l in lines)l.$1:l.$2};
    expect(m['Altitude'],'112 m (IGN)');
    expect(m['Commune'],'Plaisir (78)');
    expect(m['Adresse approchée'],'≈ Rue de la Gare 78370 Plaisir');
    expect(m['Locator QTH'],'JN18BT');
    expect(m['Azimut'],contains('vrai'));
    expect(m.containsKey('Précision'),isFalse);
    // My position: GPS altitude as fallback, GPS block, no distance.
    final mine=pointInfoLines(point:point,gps:GpsFix(accuracyM:6,altitudeM:98.6,headingDeg:45,speedMps:2,time:DateTime.utc(2026,10,30,8)));
    final g={for(final l in mine)l.$1:l.$2};
    expect(g['Altitude'],'99 m (GPS)');
    expect(g['Précision'],'± 6 m');
    expect(g['Cap'],'045°');
    expect(g['Vitesse'],'7 km/h');
    expect(g.containsKey('Distance'),isFalse);
    expect(pointInfoText('Infos du point',lines).split('\n').first,'Infos du point');
    expect(PointAction.values.contains(PointAction.info),isTrue);
  });

  test('APRS: SSID matching, heard within the hour, unique names',(){
    expect(callsignMatches('F4JPO','F4JPO-9'),isTrue);
    expect(callsignMatches('F4JPO-7','F4JPO-9'),isFalse);
    expect(callsignMatches('F4JPO','F4JPO-0'),isTrue);
    final now=DateTime.utc(2026,10,30,3);
    final heard=[(callsign:'F4JPO-9',time:now.subtract(const Duration(minutes:20)))];
    expect(heardRecently(lastHeard('F4JPO',heard),now),isTrue);
    expect(heardRecently(lastHeard('F8BOG',heard),now),isFalse);
    final groups=[{'id':'1','name':'ADRASEC 78'}];
    expect(groupNameTaken(' adrasec  78 ',groups),isTrue);
    expect(groupNameTaken('ADRASEC 78',groups,ownId:'1'),isFalse);
    expect(groupNameTaken('ADRASEC 91',groups),isFalse);
  });

  test('QRZ.com and aprs.fi links only for callsigns',(){
    expect(looksLikeCallsign('F4JPO'),isTrue);
    expect(looksLikeCallsign('F4JPO-9'),isTrue);
    expect(looksLikeCallsign('TEL-01'),isFalse);
    expect(looksLikeCallsign('PCO-demo'),isFalse);
    expect(callsignAmong(['Équipe 1',null,'f4hks']),'F4HKS');
    expect(qrzUrl('F4JPO-9'),'https://www.qrz.com/db/F4JPO');
    expect(aprsFiUrl('F4JPO-9'),'https://aprs.fi/#!call=a%2FF4JPO-9');
  });

  test('diagnostics: server lines, alert, report',(){
    final lines=serverLines({'status':'degraded','version':'0.1.2','uptime_s':93784,
      'components':{'database':'green','realtime':'green','tunnel':'orange','wakeup':'green','aprs':'off','weather':'green'},
      'resources':{'cpu_pct':12.0,'memory':{'used_mb':7000,'total_mb':8000,'pct':87.5},'disk':{'used_gb':100.0,'total_gb':1000.0,'pct':10.0}},
      'last_update':{'at':'2026-10-29T10:00:00Z','version':'0.1.2','status':'succeeded'},'last_backup':null});
    final m={for(final l in lines)l.label:l};
    expect(m['État général']!.value,'Dégradé');
    expect(m['Depuis le redémarrage']!.value,'1 j 2 h');
    expect(m['Mémoire']!.state,'red');
    expect(m['Mémoire']!.value,startsWith('88 % ⚠'));
    expect(m['Tunnel Cloudflare']!.value,'à surveiller');
    expect(m['Dernière sauvegarde']!.value,'inconnu');
    final report=diagnosticsReport(lines,at:DateTime(2026,10,30,3,20));
    expect(report,contains('SERVEUR'));
    expect(report,contains('Mémoire : 88 %'));
    expect(uptimeLabel(125),'2 min');
  });

  test('weather: rain label and the bubble of an hour',(){
    expect(rainLabel(0.4),'0,4 mm');
    final h=WeatherHour(time:DateTime.utc(2026,10,30,9),weatherCode:61,windKmh:12,windDirectionDeg:270,gustKmh:30,precipitationMm:0.4,precipitationProbability:60,apparentC:7.6);
    final lines=hourDetailLines(h);
    expect(lines.first,'Pluie');
    expect(lines,contains('Rafales 30 km/h'));
    expect(lines,contains('Pluie 0,4 mm · 60 %'));
    expect(lines,contains('Ressenti 8°'));
  });
}
