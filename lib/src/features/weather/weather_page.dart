import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/strings.dart';
import '../../models/comm_group.dart' show isPco;
import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';
import 'weather_models.dart';
import '../../ui/link_status.dart';

IconData weatherIcon(String key,{bool night=false})=>switch(key){
  'clear'=>night?Icons.nightlight_round:Icons.wb_sunny,'partly'=>night?Icons.nights_stay:Icons.wb_cloudy,'overcast'=>Icons.cloud,'fog'=>Icons.foggy,
  'drizzle'=>Icons.grain,'rain'=>Icons.water_drop,'showers'=>Icons.umbrella,'snow'=>Icons.ac_unit,
  'storm'=>Icons.thunderstorm,_=>Icons.help_outline};

/// Icons in colour (« page plus gaie », 29 Oct 2026): yellow sun, grey-blue
/// clouds, blue rain, violet storm, light blue snow; the moon in indigo.
Color weatherColor(String key,{bool night=false})=>switch(key){
  'clear'=>night?const Color(0xFF5C6BC0):const Color(0xFFF9AB00),
  'partly'=>night?const Color(0xFF7986CB):const Color(0xFFF2A600),
  'overcast'||'fog'=>const Color(0xFF78909C),
  'drizzle'||'rain'||'showers'=>const Color(0xFF1A73E8),
  'storm'=>const Color(0xFF8E24AA),'snow'=>const Color(0xFF4FC3F7),_=>const Color(0xFF9AA0A6)};

/// Temperature colour, blue when cold to orange when hot.
Color temperatureColor(double? c){
  if(c==null)return const Color(0xFF9AA0A6);
  final t=((c+5)/35).clamp(0.0,1.0);
  return Color.lerp(const Color(0xFF1A73E8),const Color(0xFFE8710A),t)!;
}

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

  /// Arrow pointing where the wind goes (it comes from [deg]).
  Widget _windArrow(int? deg,{double size=16,Color? color})=>deg==null?SizedBox(width:size):Transform.rotate(
    angle:((deg+180)%360)*3.141592653589793/180,child:Icon(Icons.navigation,size:size,color:color));

  bool _night(DateTime t,({double lat,double lon})? loc)=>loc!=null&&isNightAt(t,loc.lat,loc.lon);

  /// « Maintenant »: big icon and temperature, feels like, wind with its
  /// arrow and gusts, rain; sky gradient by day, night blue at night.
  Widget _nowCard(WeatherHour h,({double lat,double lon})? loc){
    final night=_night(DateTime.now(),loc); final key=weatherKey(h.weatherCode);
    final fg=Colors.white;
    return Container(margin:const EdgeInsets.fromLTRB(16,12,16,8),padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
        colors:night?const [Color(0xFF1A237E),Color(0xFF0D1B2A)]:const [Color(0xFF4FC3F7),Color(0xFF1A73E8)])),
      child:Row(children:[
        Container(width:76,height:76,decoration:const BoxDecoration(color:Color(0x33FFFFFF),shape:BoxShape.circle),
          child:Icon(weatherIcon(key,night:night),size:48,color:night?const Color(0xFFFFF59D):(key=='clear'||key=='partly'?const Color(0xFFFFEB3B):Colors.white))),
        const SizedBox(width:16),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(S.t('weather.now'),style:TextStyle(color:fg.withValues(alpha:0.85),fontSize:13,fontWeight:FontWeight.w600)),
          Text(_num(h.temperatureC,'°').replaceAll(' ',''),style:TextStyle(color:fg,fontSize:44,fontWeight:FontWeight.w300,height:1.05)),
          Text(S.t('weather.code.$key'),style:TextStyle(color:fg,fontSize:15,fontWeight:FontWeight.w500)),
          if(h.apparentC!=null)Text(S.t('weather.feels',{'t':_num(h.apparentC,'°').replaceAll(' ','')}),style:TextStyle(color:fg.withValues(alpha:0.85),fontSize:13)),
        ])),
        Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
          Row(mainAxisSize:MainAxisSize.min,children:[_windArrow(h.windDirectionDeg,size:18,color:fg),const SizedBox(width:4),
            Text('${windDirection(h.windDirectionDeg)} ${_num(h.windKmh,'km/h')}',style:TextStyle(color:fg,fontWeight:FontWeight.w600))]),
          if(h.gustKmh!=null)Text(S.t('weather.gusts',{'v':_num(h.gustKmh,'km/h')}),style:TextStyle(color:(h.gustKmh??0)>=70?const Color(0xFFFFCC80):fg.withValues(alpha:0.85),fontSize:12)),
          const SizedBox(height:6),
          Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.water_drop,size:14,color:fg),const SizedBox(width:3),
            Text([if(h.precipitationProbability!=null)'${h.precipitationProbability} %',if(h.precipitationMm!=null)'${h.precipitationMm!.toStringAsFixed(1)} mm'].join(' · '),
              style:TextStyle(color:fg,fontSize:12))]),
        ]),
      ]));
  }

  /// An hour of the strip touched: bubble with the detail (sky, wind,
  /// gusts, rain, feels like) — replaces the list « Heure par heure ».
  void _hourDetail(WeatherHour h,({double lat,double lon})? loc){
    final key=weatherKey(h.weatherCode); final night=_night(h.time,loc);
    showDialog<void>(context:context,builder:(c)=>AlertDialog(
      icon:Icon(weatherIcon(key,night:night),color:weatherColor(key,night:night),size:36),
      title:Text('${_hm(h.time)} · ${_num(h.temperatureC,'°').replaceAll(' ','')}'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        for(final line in hourDetailLines(h))Padding(padding:const EdgeInsets.symmetric(vertical:2),child:Text(line)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:Text(S.t('common.close')))]));
  }

  /// 24 h at a glance: « Maintenant » first in a blue pill, coloured
  /// temperature, wind arrow with its speed, rain when above 0; sunrise
  /// and sunset as small marks between two hours, with their time.
  Widget _strip(List<WeatherHour> hours,({double lat,double lon})? loc){
    final s=Theme.of(context).colorScheme;
    final cells=<Widget>[];
    for(var i=0;i<hours.length&&i<24;i++){
      final h=hours[i]; final night=_night(h.time,loc); final key=weatherKey(h.weatherCode); final now=i==0;
      final fg=now?s.onPrimary:s.onSurfaceVariant;
      final mm=h.precipitationMm??0;
      cells.add(InkWell(key:ValueKey('weather-hour-$i'),borderRadius:BorderRadius.circular(16),onTap:()=>_hourDetail(h,loc),child:Container(width:62,margin:const EdgeInsets.symmetric(horizontal:2,vertical:6),padding:const EdgeInsets.symmetric(vertical:6),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(16),
          color:now?s.primary:(h.gustKmh??0)>=70?Colors.orange.withValues(alpha:0.15):s.surfaceContainer),
        child:Column(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Text(now?S.t('weather.now'):_hm(h.time),style:TextStyle(fontSize:11,fontWeight:now?FontWeight.w700:FontWeight.w500,color:now?s.onPrimary:s.onSurfaceVariant)),
          Icon(weatherIcon(key,night:night),size:24,color:now?s.onPrimary:weatherColor(key,night:night)),
          Text(_num(h.temperatureC,'°').replaceAll(' ',''),style:TextStyle(fontWeight:FontWeight.w700,fontSize:15,color:now?s.onPrimary:temperatureColor(h.temperatureC))),
          _windArrow(h.windDirectionDeg,size:14,color:fg),
          // Wind speed under the arrow; rain only when there is some (lot 5).
          Text(h.windKmh==null?'':'${h.windKmh!.round()}',style:TextStyle(fontSize:11,fontWeight:FontWeight.w600,color:fg)),
          if(mm>0)Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.water_drop,size:10,color:now?s.onPrimary:const Color(0xFF1A73E8)),
            Text(rainLabel(mm),style:TextStyle(fontSize:10,color:now?s.onPrimary:const Color(0xFF1A73E8)))])
          else const SizedBox(height:12),
        ]))));
      final ev=loc==null?null:sunEventIn(h.time,loc.lat,loc.lon);
      if(ev!=null){
        cells.add(SizedBox(width:40,child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(ev.kind=='rise'?Icons.wb_twilight:Icons.nights_stay_outlined,size:18,color:const Color(0xFFE8710A)),
          Container(width:2,height:30,color:const Color(0xFFE8710A).withValues(alpha:0.5)),
          Text(_hm(ev.at),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:Color(0xFFE8710A))),
        ])));
      }
    }
    return SizedBox(height:150,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:12),children:cells));
  }

  @override Widget build(BuildContext context){
    final r=_report; final now=DateTime.now();
    final hours=r?.upcoming(now)??const <WeatherHour>[];
    final loc=widget.point!=null?(lat:widget.point!.lat,lon:widget.point!.lon):(r?.lat!=null&&r?.lon!=null?(lat:r!.lat!,lon:r.lon!):widget.fallback);
    final title=widget.point==null?S.t('weather.title'):S.t('weather.pointTitle',{'label':widget.point!.label});
    final t=Theme.of(context); final s=t.colorScheme;
    return Scaffold(
      appBar:LinkedAppBar(title:Text(title),secondary:[
        // « Diffuser » written on a wide screen (revue n° 51); in ⋮ on a
        // phone with « Actualiser », so the title shows whole (card C3).
        if(widget.point==null&&isPco(widget.actorId))AppBarAction(icon:Icons.campaign_outlined,label:S.t('weather.broadcast'),onPressed:_bulletin,written:true),
        AppBarAction(icon:Icons.refresh,label:S.t('weather.refresh'),onPressed:widget.point==null?_refresh:_load),
      ]),
      body:RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.only(bottom:24),children:[
        if(_loading)const LinearProgressIndicator(),
        // Vigilance first, as a coloured band.
        if(r?.vigilance!=null)Container(margin:const EdgeInsets.fromLTRB(16,12,16,0),padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(color:vigilanceColor(r!.vigilance!.colorId).withValues(alpha:0.18),borderRadius:BorderRadius.circular(14),
            border:Border(left:BorderSide(color:vigilanceColor(r.vigilance!.colorId),width:6))),
          child:Row(children:[Icon(Icons.warning_amber,color:vigilanceColor(r.vigilance!.colorId)),const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(S.t('weather.vigilance.${r.vigilance!.colorId.clamp(1,4)}',{'dep':r.vigilance!.department}),style:const TextStyle(fontWeight:FontWeight.w600)),
              if(r.vigilance!.phenomena.isNotEmpty)Text(r.vigilance!.phenomena.join(', '),style:t.textTheme.bodySmall),
            ]))])),
        if(weatherShowsStale(r,offline:_offline))ListTile(leading:const Icon(Icons.history),title:Text(S.t('weather.stale',{'time':_hm(r!.fetchedAt)}))),
        if(r==null||r.isEmpty)Padding(padding:const EdgeInsets.all(20),child:Text(_loading?S.t('weather.loading'):S.t('weather.none'))),
        if(hours.isNotEmpty)_nowCard(hours.first,loc),
        if(hours.isNotEmpty)_strip(hours,loc),
        // Temperatures over 24 h.
        if(hours.where((h)=>h.temperatureC!=null).length>=2)Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),child:Card(elevation:0,child:Padding(
          padding:const EdgeInsets.fromLTRB(12,10,12,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(S.t('weather.curve'),style:t.textTheme.titleSmall),
            const SizedBox(height:6),
            SizedBox(height:90,child:CustomPaint(size:Size.infinite,painter:_TempCurve([for(final h in hours.take(24))h.temperatureC],s.onSurfaceVariant))),
          ])))),
        if(r?.provider!=null)Padding(padding:const EdgeInsets.all(16),child:Text(S.t('weather.source',{'provider':r!.provider}),style:t.textTheme.bodySmall)),
      ])),
    );
  }
}

/// Temperature curve, each point in its colour.
class _TempCurve extends CustomPainter {
  final List<double?> values; final Color label;
  _TempCurve(this.values,this.label);
  @override void paint(Canvas canvas,Size size){
    final pts=[for(var i=0;i<values.length;i++)if(values[i]!=null)(i,values[i]!)];
    if(pts.length<2)return;
    final lo=pts.map((p)=>p.$2).reduce((a,b)=>a<b?a:b), hi=pts.map((p)=>p.$2).reduce((a,b)=>a>b?a:b);
    final span=(hi-lo).abs()<1?1.0:hi-lo;
    Offset at((int,double) p)=>Offset(size.width*p.$1/(values.length-1),12+(size.height-28)*(1-(p.$2-lo)/span));
    for(var i=1;i<pts.length;i++){
      canvas.drawLine(at(pts[i-1]),at(pts[i]),Paint()..strokeWidth=3..strokeCap=StrokeCap.round..color=temperatureColor((pts[i-1].$2+pts[i].$2)/2));
    }
    for(final p in [pts.first,pts.reduce((a,b)=>a.$2>=b.$2?a:b),pts.reduce((a,b)=>a.$2<=b.$2?a:b)]){
      final tp=TextPainter(text:TextSpan(text:'${p.$2.round()}°',style:TextStyle(fontSize:11,color:label,fontWeight:FontWeight.w600)),textDirection:TextDirection.ltr)..layout();
      final o=at(p);
      tp.paint(canvas,Offset((o.dx-tp.width/2).clamp(0.0,size.width-tp.width),o.dy-tp.height-2<0?o.dy+4:o.dy-tp.height-2));
    }
  }
  @override bool shouldRepaint(covariant _TempCurve old)=>old.values!=values;
}
