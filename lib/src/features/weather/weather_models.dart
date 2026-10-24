/// Weather forecasts (note « Prévisions météo »): Météo-France first, through
/// the server which keeps the last forecast for offline use; vigilance of
/// the department; sunrise and sunset also computed on the device. Pure code.
library;

import 'dart:math' as math;

class WeatherHour {
  final DateTime time; final double? temperatureC, apparentC, precipitationMm, windKmh, gustKmh;
  final int? precipitationProbability, weatherCode, windDirectionDeg, cloudCoverPct;
  final double? visibilityM;
  const WeatherHour({required this.time,this.temperatureC,this.apparentC,this.precipitationMm,this.windKmh,this.gustKmh,
    this.precipitationProbability,this.weatherCode,this.windDirectionDeg,this.cloudCoverPct,this.visibilityM});

  static double? _d(Object? v)=>v is num?v.toDouble():null;
  static int? _i(Object? v)=>v is num?v.round():null;

  factory WeatherHour.fromJson(Map<String,dynamic> j)=>WeatherHour(
    time:DateTime.parse(j['time'] as String),temperatureC:_d(j['temperature_c']),apparentC:_d(j['apparent_c']),
    precipitationMm:_d(j['precipitation_mm']),windKmh:_d(j['wind_kmh']),gustKmh:_d(j['gust_kmh']),
    precipitationProbability:_i(j['precipitation_probability']),weatherCode:_i(j['weather_code']),
    windDirectionDeg:_i(j['wind_direction_deg']),cloudCoverPct:_i(j['cloud_cover_pct']),visibilityM:_d(j['visibility_m']));
}

class Vigilance {
  final String department; final int colorId; final List<String> phenomena;
  const Vigilance({required this.department,required this.colorId,this.phenomena=const []});
  factory Vigilance.fromJson(Map<String,dynamic> j)=>Vigilance(department:'${j['department']??''}',
    colorId:(j['color_id'] as num?)?.toInt()??1,phenomena:[for(final p in (j['phenomena'] as List?)??const [])'$p']);
  bool get isAlert=>colorId>=3;
}

class WeatherReport {
  final String? provider; final DateTime? fetchedAt; final bool stale;
  final List<WeatherHour> hours; final List<({String date,DateTime? sunrise,DateTime? sunset})> days;
  final Vigilance? vigilance; final double? lat, lon;
  const WeatherReport({this.provider,this.fetchedAt,this.stale=true,this.hours=const [],this.days=const [],this.vigilance,this.lat,this.lon});

  /// Answer of `GET /events/{id}/weather` or `GET /weather`.
  factory WeatherReport.fromJson(Map<String,dynamic> j){
    final f=j['forecast'] is Map?Map<String,dynamic>.from(j['forecast'] as Map):(j['hourly'] is List?j:null);
    final v=j['vigilance'];
    return WeatherReport(
      provider:(f?['provider_label'] as String?)??(f?['provider'] as String?),
      fetchedAt:f?['fetched_at']==null?null:DateTime.tryParse('${f!['fetched_at']}'),
      stale:j['stale']==true,
      hours:[for(final h in (f?['hourly'] as List?)??const []) if(h is Map) WeatherHour.fromJson(Map<String,dynamic>.from(h))],
      days:[for(final d in (f?['daily'] as List?)??const []) if(d is Map)(date:'${d['date']}',
        sunrise:DateTime.tryParse('${d['sunrise']}'),sunset:DateTime.tryParse('${d['sunset']}'))],
      vigilance:v is Map?Vigilance.fromJson(Map<String,dynamic>.from(v)):null,
      lat:(f?['lat'] as num?)?.toDouble(),lon:(f?['lon'] as num?)?.toDouble(),
    );
  }

  bool get isEmpty=>hours.isEmpty;

  /// Next [n] hours from [now].
  List<WeatherHour> upcoming(DateTime now,{int n=48}){
    final start=DateTime.utc(now.toUtc().year,now.toUtc().month,now.toUtc().day,now.toUtc().hour);
    return hours.where((h)=>!h.time.toUtc().isBefore(start)).take(n).toList();
  }
}

/// WMO weather codes → icon family and translation key.
String weatherKey(int? code){
  if(code==null)return 'unknown';
  if(code==0)return 'clear';
  if(code<=2)return 'partly';
  if(code==3)return 'overcast';
  if(code==45||code==48)return 'fog';
  if(code>=51&&code<=57)return 'drizzle';
  if(code>=61&&code<=67)return 'rain';
  if(code>=71&&code<=77)return 'snow';
  if(code>=80&&code<=82)return 'showers';
  if(code==85||code==86)return 'snow';
  if(code>=95)return 'storm';
  return 'unknown';
}

/// Cardinal direction of the wind (where it comes from).
String windDirection(int? deg){
  if(deg==null)return '';
  const names=['N','NE','E','SE','S','SO','O','NO'];
  return names[((deg%360)/45).round()%8];
}

/// Sunrise and sunset (UTC) for a day and place, NOAA algorithm, so that
/// they are known offline. Null near the poles when the sun does not rise
/// or set.
({DateTime? sunrise,DateTime? sunset}) sunTimes(DateTime day,double lat,double lon){
  double rad(double d)=>d*math.pi/180;
  double deg(double r)=>r*180/math.pi;
  final n=DateTime.utc(day.year,day.month,day.day).difference(DateTime.utc(day.year,1,1)).inDays+1;
  final gamma=2*math.pi/365*(n-1);
  final eqtime=229.18*(0.000075+0.001868*math.cos(gamma)-0.032077*math.sin(gamma)-0.014615*math.cos(2*gamma)-0.040849*math.sin(2*gamma));
  final decl=0.006918-0.399912*math.cos(gamma)+0.070257*math.sin(gamma)-0.006758*math.cos(2*gamma)+0.000907*math.sin(2*gamma)
    -0.002697*math.cos(3*gamma)+0.00148*math.sin(3*gamma);
  final cosHa=math.cos(rad(90.833))/(math.cos(rad(lat))*math.cos(decl))-math.tan(rad(lat))*math.tan(decl);
  if(cosHa<-1||cosHa>1)return (sunrise:null,sunset:null);
  final ha=deg(math.acos(cosHa));
  DateTime at(double minutes)=>DateTime.utc(day.year,day.month,day.day).add(Duration(seconds:(minutes*60).round()));
  return (sunrise:at(720-4*(lon+ha)-eqtime),sunset:at(720-4*(lon-ha)-eqtime));
}
