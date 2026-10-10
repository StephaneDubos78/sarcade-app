import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco;
import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';
import 'weather_models.dart';

IconData weatherIcon(String key)=>switch(key){
  'clear'=>Icons.wb_sunny,'partly'=>Icons.wb_cloudy_outlined,'overcast'=>Icons.cloud,'fog'=>Icons.foggy,
  'drizzle'=>Icons.grain,'rain'=>Icons.water_drop,'showers'=>Icons.umbrella,'snow'=>Icons.ac_unit,
  'storm'=>Icons.thunderstorm,_=>Icons.help_outline};

Color vigilanceColor(int id)=>switch(id){2=>Colors.yellow.shade600,3=>Colors.orange,4=>Colors.red,_=>Colors.green};

/// Forecast of the event (or of a designated point): next 48 hours,
/// vigilance, sun times. Kept on the device for offline use; compact answer
/// in low-bandwidth mode.
class WeatherPage extends StatefulWidget {
  final SarcadeApi api; final LocalStore store; final String eventId, actorId; final bool lowBandwidth;
  /// Designated point instead of the event forecast.
  final ({double lat,double lon,String label})? point;
  /// Fallback location for offline sun times.
  final ({double lat,double lon})? fallback;
  const WeatherPage({super.key,required this.api,required this.store,required this.eventId,required this.actorId,
    this.lowBandwidth=false,this.point,this.fallback});
  @override State<WeatherPage> createState()=>_WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  WeatherReport? _report; bool _loading=true; bool _offline=false;

  String get _cacheKey=>widget.point==null?'weather:${widget.eventId}':'weather:point';

  @override void initState(){
    super.initState();
    final cached=widget.store.cachedJson(_cacheKey);
    if(cached!=null&&widget.point==null)_report=WeatherReport.fromJson(cached);
    _load();
  }

  Future<void> _load() async {
    setState(()=>_loading=true);
    try{
      final p=widget.point;
      final j=p==null?await widget.api.eventWeather(widget.eventId,compact:widget.lowBandwidth):await widget.api.pointWeather(p.lat,p.lon);
      await widget.store.cacheJson(_cacheKey,j);
      _report=WeatherReport.fromJson(j); _offline=false;
    }catch(_){
      _offline=true;
    }finally{
      if(mounted)setState(()=>_loading=false);
    }
  }

  Future<void> _refresh() async {
    final messenger=ScaffoldMessenger.of(context);
    try{await widget.api.refreshWeather(widget.eventId);}catch(_){messenger.showSnackBar(SnackBar(content:Text(S.t('weather.refreshFailed'))));}
    await _load();
  }

  Future<void> _bulletin() async {
    final messenger=ScaffoldMessenger.of(context);
    try{
      final text=await widget.api.weatherBulletin(widget.eventId);
      await Clipboard.setData(ClipboardData(text:text));
      messenger.showSnackBar(SnackBar(content:Text(S.t('weather.bulletinCopied'))));
    }catch(_){messenger.showSnackBar(SnackBar(content:Text(S.t('weather.bulletinFailed'))));}
  }

  String _hm(DateTime? t){if(t==null)return '-';final l=t.toLocal();return '${l.hour.toString().padLeft(2,'0')}:${l.minute.toString().padLeft(2,'0')}';}
  String _num(double? v,String unit)=>v==null?'-':'${v.round()} $unit';

  @override Widget build(BuildContext context){
    final r=_report; final now=DateTime.now();
    final hours=r?.upcoming(now)??const <WeatherHour>[];
    final loc=widget.point!=null?(lat:widget.point!.lat,lon:widget.point!.lon):(r?.lat!=null&&r?.lon!=null?(lat:r!.lat!,lon:r.lon!):widget.fallback);
    final today=r?.days.isNotEmpty==true?r!.days.first:null;
    final sun=loc==null?null:sunTimes(now.toUtc(),loc.lat,loc.lon);
    final title=widget.point==null?S.t('weather.title'):S.t('weather.pointTitle',{'label':widget.point!.label});
    return Scaffold(
      appBar:AppBar(title:Text(title),actions:[
        if(widget.point==null&&isPco(widget.actorId))IconButton(tooltip:S.t('weather.bulletin'),onPressed:_bulletin,icon:const Icon(Icons.campaign_outlined)),
        IconButton(tooltip:S.t('weather.refresh'),onPressed:widget.point==null?_refresh:_load,icon:const Icon(Icons.refresh)),
      ]),
      body:RefreshIndicator(onRefresh:_load,child:ListView(children:[
        if(_loading)const LinearProgressIndicator(),
        if(r?.vigilance!=null)Material(color:vigilanceColor(r!.vigilance!.colorId),child:ListTile(
          leading:const Icon(Icons.warning_amber),
          title:Text(S.t('weather.vigilance.${r.vigilance!.colorId.clamp(1,4)}',{'dep':r.vigilance!.department})),
          subtitle:r.vigilance!.phenomena.isEmpty?null:Text(r.vigilance!.phenomena.join(', ')),
        )),
        if(r!=null&&(r.stale||_offline))ListTile(leading:const Icon(Icons.history),title:Text(S.t('weather.stale',{'time':_hm(r.fetchedAt)}))),
        if(r==null||r.isEmpty)Padding(padding:const EdgeInsets.all(20),child:Text(_loading?S.t('weather.loading'):S.t('weather.none'))),
        ListTile(leading:const Icon(Icons.wb_twilight),
          title:Text(S.t('weather.sun',{'rise':_hm(today?.sunrise??sun?.sunrise),'set':_hm(today?.sunset??sun?.sunset)}))),
        for(final h in hours)ListTile(
          dense:true,
          leading:Icon(weatherIcon(weatherKey(h.weatherCode))),
          title:Text('${_hm(h.time)} · ${S.t('weather.code.${weatherKey(h.weatherCode)}')} · ${_num(h.temperatureC,'°C')}'),
          subtitle:Text([
            S.t('weather.wind',{'dir':windDirection(h.windDirectionDeg),'speed':_num(h.windKmh,'km/h'),'gust':_num(h.gustKmh,'km/h')}),
            if(h.precipitationMm!=null)S.t('weather.rain',{'mm':h.precipitationMm!.toStringAsFixed(1)}),
            if(h.precipitationProbability!=null)'${h.precipitationProbability} %',
          ].join(' · ')),
          tileColor:(h.gustKmh??0)>=70?Colors.orange.withValues(alpha:0.12):null,
        ),
        if(r?.provider!=null)Padding(padding:const EdgeInsets.all(16),child:Text(S.t('weather.source',{'provider':r!.provider}),style:Theme.of(context).textTheme.bodySmall)),
      ])),
    );
  }
}
