/// Convertisseur de coordonnées (menu Outils, 29 Oct 2026; étoffé par le
/// lot 5, validated on 30 Oct 2026, 2 h 11): source of the position (my
/// position live by default, touch the map, an operator / high point /
/// relay / point of interest or an address by search, typed text), guided
/// input (recognised format, separate fields per format, dictation),
/// every output format (Lambert 93 and DFCI included, MGRS precision),
/// draggable mini map, radio reading, big characters, actions, history of
/// the last 10 conversions. Same presentation of the formats as the fiche
/// « Infos du point ».
library;

import '../../ui/choice_pills.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../../offline/local_store.dart';
import '../../services/location_service.dart';
import '../dictation/dictation_button.dart';
import '../measure/coordinate_rows.dart';
import '../measure/coordinates.dart';
import '../search/map_search.dart';
import 'converter_input.dart';
import 'paste_locations.dart';
import '../../ui/link_status.dart';

enum ConverterSource { me, map, search, input }

/// Actions handed back to the map (the converter closes first).
class ConverterActions {
  final void Function(LatLng)? show, measure, poi, bearing, order;
  final void Function(String text)? message;
  /// « Toucher la carte »: the converter closes, the map is touched, the
  /// converter opens again on that point.
  final VoidCallback? pickOnMap;
  const ConverterActions({this.show,this.measure,this.poi,this.bearing,this.order,this.message,this.pickOnMap});
}

class CoordinateConverterPage extends StatefulWidget {
  final LatLng? initial;
  final void Function(LatLng)? onShow, onMeasure;
  final ConverterActions actions;
  final LocationService? location; final LocalStore? store;
  /// Operators, high points, relays, points of interest of the event.
  final Iterable<Searchable> Function()? items;
  final Future<List<SearchResult>> Function(String query,LatLng? near)? addresses;
  final String tileUrl;
  const CoordinateConverterPage({super.key,this.initial,this.onShow,this.onMeasure,this.actions=const ConverterActions(),
    this.location,this.store,this.items,this.addresses,this.tileUrl=''});
  @override State<CoordinateConverterPage> createState()=>_CoordinateConverterPageState();
}

class _CoordinateConverterPageState extends State<CoordinateConverterPage> {
  late final TextEditingController _text=TextEditingController(text:widget.initial==null?'':formatDd(widget.initial!));
  late ConverterSource _source=widget.initial!=null?ConverterSource.input:widget.location!=null?ConverterSource.me:ConverterSource.input;
  LatLng? _picked, _live; String? _pickedLabel; StreamSubscription? _gps;
  CoordFormat _guided=CoordFormat.dd; bool _fields=false; int _mgrsDigits=4;
  final _search=TextEditingController(); List<SearchResult> _results=const []; Timer? _debounce;
  final _mini=MapController();
  List<Map<String,dynamic>> _history=[];
  static const _historyKey='converter_history';

  @override void initState(){
    super.initState();
    _history=_readHistory();
    if(_source==ConverterSource.me)_startGps();
  }
  @override void dispose(){_gps?.cancel();_debounce?.cancel();_text.dispose();_search.dispose();_paste.dispose();super.dispose();}

  List<Map<String,dynamic>> _readHistory(){
    try{final v=widget.store?.preference(_historyKey);if(v==null)return [];
      return [for(final e in jsonDecode(v) as List)Map<String,dynamic>.from(e as Map)];}catch(_){return [];}
  }
  void _remember(LatLng p,String label){
    final list=pushHistory(_history,p,label);
    setState(()=>_history=list);
    unawaited(widget.store?.setPreference(_historyKey,jsonEncode(list)));
  }

  Future<void> _startGps() async {
    final loc=widget.location; if(loc==null)return;
    if(!await loc.ensurePermission())return;
    final first=await loc.current();
    if(mounted&&first!=null)setState(()=>_live=LatLng(first.latitude,first.longitude));
    _gps?.cancel();
    _gps=loc.positions().listen((p){if(mounted&&_source==ConverterSource.me)setState(()=>_live=LatLng(p.latitude,p.longitude));},onError:(_){});
  }

  void _setSource(ConverterSource s){
    setState(()=>_source=s);
    if(s==ConverterSource.me){_startGps();}else{_gps?.cancel();_gps=null;}
    if(s==ConverterSource.map){
      final pick=widget.actions.pickOnMap;
      if(pick!=null){final nav=Navigator.of(context);if(nav.canPop())nav.pop();pick();}
    }
  }

  LatLng? get _point=>switch(_source){
    ConverterSource.me=>_live,
    ConverterSource.map||ConverterSource.search=>_picked,
    ConverterSource.input=>parseCoordinates(_text.text),
  };

  String get _label=>switch(_source){
    ConverterSource.me=>S.t('info.myPosition'),
    ConverterSource.map||ConverterSource.search=>_pickedLabel??S.t('nav.point'),
    ConverterSource.input=>_text.text.trim(),
  };

  void _searchChanged(String q){
    final local=widget.items==null?const <SearchResult>[]:searchLocal(q,widget.items!());
    setState(()=>_results=local);
    _debounce?.cancel();
    final addr=widget.addresses;
    if(addr==null||q.trim().length<3)return;
    _debounce=Timer(const Duration(milliseconds:400),() async {
      try{final r=await addr(q.trim(),_live);if(mounted&&_search.text==q)setState(()=>_results=[...local,...r]);}catch(_){/* offline: local only */}
    });
  }

  void _pickResult(SearchResult r){
    FocusScope.of(context).unfocus();
    setState((){_picked=r.point;_pickedLabel=r.title;_results=const [];});
    _remember(r.point,r.title);
    _moveMini(r.point);
  }

  void _moveMini(LatLng p){try{_mini.move(p,_mini.camera.zoom);}catch(_){/* not built yet */}}

  void _act(void Function(LatLng)? f){
    final p=_point; if(p==null||f==null)return;
    _remember(p,_label);
    final nav=Navigator.of(context);
    if(nav.canPop())nav.pop();
    f(p);
  }

  /// The mini map was dragged: the point becomes a typed position.
  void _dragged(LatLng p){
    setState((){_source=ConverterSource.input;_text.text=formatDd(p,decimal:'.');});
    _gps?.cancel();_gps=null;
  }

  Widget _sourceChips(){
    Widget chip(ConverterSource s,IconData icon,String key)=>ChoiceChip(key:ValueKey('src-${s.name}'),avatar:Icon(icon,size:18),
      label:Text(S.t(key)),selected:_source==s,onSelected:(_)=>_setSource(s));
    return Wrap(spacing:8,runSpacing:8,children:[
      if(widget.location!=null)chip(ConverterSource.me,Icons.my_location,'converter.src.me'),
      if(widget.actions.pickOnMap!=null)chip(ConverterSource.map,Icons.touch_app_outlined,'converter.src.map'),
      if(widget.items!=null||widget.addresses!=null)chip(ConverterSource.search,Icons.search,'converter.src.search'),
      chip(ConverterSource.input,Icons.keyboard_outlined,'converter.src.input'),
    ]);
  }

  Widget _input(ThemeData t){
    final detected=detectFormat(_text.text);
    final invalid=_text.text.trim().isNotEmpty&&parseCoordinates(_text.text)==null;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[
        Expanded(child:ChoicePills<bool>(choices:[
          (value:false,label:S.t('converter.free'),icon:null),(value:true,label:S.t('converter.fields'),icon:null)],
          selected:_fields,onSelected:(v)=>setState(()=>_fields=v))),
      ]),
      const SizedBox(height:10),
      if(!_fields)TextField(key:const ValueKey('converter-input'),controller:_text,autofocus:widget.initial==null&&widget.location==null,onChanged:(_)=>setState((){}),
        decoration:InputDecoration(labelText:S.t('converter.input'),hintText:'48°48,074 N 2°08,074 E · 31U DQ 4823 0611',
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),
          helperText:detected==null?null:S.t('converter.recognised',{'f':formatLabel(detected)}),
          suffixIcon:Row(mainAxisSize:MainAxisSize.min,children:[
            if(_text.text.isNotEmpty)IconButton(tooltip:S.t('common.close'),onPressed:()=>setState(_text.clear),icon:const Icon(Icons.clear)),
            DictationButton(controller:_text,onChanged:()=>setState((){})),
          ]),
          errorText:invalid?S.t('converter.invalid'):null))
      else ...[
        DropdownButtonFormField<CoordFormat>(initialValue:_guided,decoration:InputDecoration(labelText:S.t('converter.format'),isDense:true,
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))),
          items:[for(final f in guidedFormats)DropdownMenuItem(value:f,child:Text(formatLabel(f)))],
          onChanged:(f){if(f!=null)setState(()=>_guided=f);}),
        const SizedBox(height:10),
        GuidedFields(key:ValueKey('guided-${_guided.name}'),format:_guided,onText:(v)=>setState(()=>_text.text=v)),
        if(invalid)Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t('converter.invalid'),style:TextStyle(color:t.colorScheme.error))),
      ],
    ]);
  }

  // --- « Coller » (card of 30 Oct 2026, 16 h 34), text part ---------------
  final _paste=TextEditingController();
  List<FoundLocation>? _found; String? _pasteNote; bool _pasting=false;

  Future<void> _pasteFromClipboard() async {
    final d=await Clipboard.getData(Clipboard.kTextPlain);
    final text=d?.text??'';
    if(text.trim().isEmpty){setState(()=>_pasteNote=S.t('paste.empty'));return;}
    _paste.text=text;
    await _readPasted();
  }

  /// Reads the pasted text; nothing is applied without a touch on a result.
  Future<void> _readPasted() async {
    final text=_paste.text;
    if(text.trim().isEmpty){setState((){_found=null;_pasteNote=null;});return;}
    var found=findLocations(text);
    String? note;
    // Last resort: an address (geocoding of the server).
    final addr=widget.addresses;
    if(found.isEmpty&&addr!=null&&text.trim().length>=3&&text.trim().length<=200){
      setState(()=>_pasting=true);
      try{
        final r=await addr(text.trim(),_live);
        found=[for(final x in r.take(5))(point:x.point,excerpt:x.title,format:'address')];
      }catch(_){note=S.t('paste.offline');}
      if(!mounted)return;
    }
    setState((){_pasting=false;_found=found;_pasteNote=note??(found.isEmpty?S.t('paste.none'):null);});
  }

  void _usePasted(FoundLocation f){
    setState((){
      _source=ConverterSource.input;_fields=false;
      _text.text=formatDd(f.point,decimal:'.');
      _found=null;_pasteNote=S.t('paste.applied',{'what':f.excerpt});
    });
    _gps?.cancel();_gps=null;
    _remember(f.point,f.excerpt);
  }

  String _formatName(String f)=>switch(f){
    'link'=>S.t('paste.link'),'address'=>S.t('paste.address'),
    _=>formatLabel(CoordFormat.values.firstWhere((c)=>c.name==f,orElse:()=>CoordFormat.dd))};

  Widget _pasteZone(ThemeData t){
    final found=_found;
    return Card(key:const ValueKey('converter-paste'),margin:EdgeInsets.zero,child:Padding(padding:const EdgeInsets.fromLTRB(12,10,12,10),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          const Icon(Icons.content_paste),const SizedBox(width:8),
          Expanded(child:Text(S.t('paste.title'),style:t.textTheme.titleSmall)),
          FilledButton.tonalIcon(key:const ValueKey('paste-button'),onPressed:_pasteFromClipboard,icon:const Icon(Icons.content_paste_go),label:Text(S.t('paste.button'))),
        ]),
        const SizedBox(height:8),
        TextField(key:const ValueKey('paste-text'),controller:_paste,minLines:1,maxLines:4,onSubmitted:(_)=>_readPasted(),
          decoration:InputDecoration(isDense:true,hintText:S.t('paste.hint'),border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),
            suffixIcon:IconButton(tooltip:S.t('paste.read'),onPressed:_readPasted,icon:const Icon(Icons.travel_explore)))),
        if(_pasting)const Padding(padding:EdgeInsets.only(top:8),child:LinearProgressIndicator()),
        if(_pasteNote!=null)Padding(padding:const EdgeInsets.only(top:6),child:Text(_pasteNote!,style:t.textTheme.bodySmall)),
        if(found!=null&&found.isNotEmpty)...[
          Padding(padding:const EdgeInsets.only(top:6),child:Text(S.t(found.length==1?'paste.foundOne':'paste.foundMany',{'n':found.length}),style:t.textTheme.bodySmall)),
          for(final f in found)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:const Icon(Icons.place_outlined),
            title:Text(S.t('paste.read1',{'what':f.excerpt}),maxLines:2,overflow:TextOverflow.ellipsis),
            subtitle:Text('${_formatName(f.format)} · ${formatDd(f.point)}'),
            trailing:FilledButton(onPressed:()=>_usePasted(f),child:Text(S.t('paste.use')))),
        ],
      ])));
  }

  Widget _searchBox(){
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      TextField(key:const ValueKey('converter-search'),controller:_search,onChanged:_searchChanged,
        decoration:InputDecoration(prefixIcon:const Icon(Icons.search),labelText:S.t('converter.searchHint'),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),
          suffixIcon:DictationButton(controller:_search,onChanged:()=>_searchChanged(_search.text)))),
      for(final r in _results.take(8))ListTile(dense:true,leading:const Icon(Icons.place_outlined),title:Text(r.title,maxLines:1,overflow:TextOverflow.ellipsis),
        subtitle:Text([S.t('search.kind.${r.kind.name}'),if(r.subtitle.isNotEmpty)r.subtitle].join(' · '),maxLines:1,overflow:TextOverflow.ellipsis),onTap:()=>_pickResult(r)),
      if(_picked!=null&&_results.isEmpty)Padding(padding:const EdgeInsets.only(top:6),child:Text(_pickedLabel??'',style:const TextStyle(fontWeight:FontWeight.w600))),
    ]);
  }

  Widget _miniMap(LatLng p){
    if(widget.tileUrl.isEmpty)return const SizedBox.shrink();
    return ClipRRect(borderRadius:BorderRadius.circular(14),child:SizedBox(height:180,child:Stack(children:[
      FlutterMap(mapController:_mini,options:MapOptions(initialCenter:p,initialZoom:14,
          onPositionChanged:(camera,gesture){if(gesture)_dragged(camera.center);}),
        children:[TileLayer(urlTemplate:widget.tileUrl,userAgentPackageName:'org.sarcade.app')]),
      const IgnorePointer(child:Center(child:Padding(padding:EdgeInsets.only(bottom:30),child:Icon(Icons.location_on,size:36,color:Colors.red)))),
      Positioned(left:8,bottom:6,child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
        decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(8)),
        child:Text(S.t('converter.drag'),style:const TextStyle(color:Colors.white,fontSize:11)))),
    ])));
  }

  @override
  Widget build(BuildContext context){
    final t=Theme.of(context); final p=_point;
    if(p!=null&&_source!=ConverterSource.input)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_moveMini(p);});
    final a=widget.actions;
    final show=a.show??widget.onShow, measure=a.measure??widget.onMeasure;
    final formats=converterFormats;
    return Scaffold(
      appBar:LinkedAppBar(title:Text(S.t('converter.title'))),
      body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
        Text(S.t('converter.help'),style:t.textTheme.bodyMedium?.copyWith(color:t.colorScheme.onSurfaceVariant)),
        const SizedBox(height:12),
        _pasteZone(t),
        const SizedBox(height:12),
        _sourceChips(),
        const SizedBox(height:12),
        if(_source==ConverterSource.input)_input(t),
        if(_source==ConverterSource.search)_searchBox(),
        if(_source==ConverterSource.me&&_live==null)ListTile(leading:const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)),title:Text(S.t('converter.waitingGps'))),
        if(_source==ConverterSource.map&&_picked==null)ListTile(leading:const Icon(Icons.touch_app_outlined),title:Text(S.t('converter.touchMap'))),
        const SizedBox(height:12),
        if(p!=null)...[
          _miniMap(p),
          const SizedBox(height:12),
          InfoBlock(title:S.t('info.coordinates'),trailing:PopupMenuButton<int>(tooltip:S.t('converter.mgrsPrecision'),initialValue:_mgrsDigits,
              icon:const Icon(Icons.tune),onSelected:(v)=>setState(()=>_mgrsDigits=v),
              itemBuilder:(_)=>[for(final d in const [2,3,4,5])CheckedPopupMenuItem(value:d,checked:d==_mgrsDigits,
                child:Text(S.t('converter.mgrsDigits',{'m':const {2:'1 km',3:'100 m',4:'10 m',5:'1 m'}[d]})))]),
            children:coordinateRows(p,formats,mgrsDigits:_mgrsDigits)),
          Wrap(spacing:8,runSpacing:8,children:[
            FilledButton.icon(style:FilledButton.styleFrom(shape:const StadiumBorder()),onPressed:(){_remember(p,_label);
                copyText(context,[_label,coordinatesText(p,formats,mgrsDigits:_mgrsDigits)].where((s)=>s.isNotEmpty).join('\n'));},
              icon:const Icon(Icons.copy_all),label:Text(S.t('info.copyAll'))),
            if(a.message!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),onPressed:(){
                final text=[_label,coordinatesText(p,formats,mgrsDigits:_mgrsDigits)].where((s)=>s.isNotEmpty).join('\n');
                _act((_)=>a.message!(text));},
              icon:const Icon(Icons.send_outlined),label:Text(S.t('info.send'))),
            if(show!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(show),icon:const Icon(Icons.center_focus_strong),label:Text(S.t('converter.show'))),
            if(measure!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(measure),icon:const Icon(Icons.straighten),label:Text(S.t('converter.measure'))),
            if(a.poi!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(a.poi),icon:const Icon(Icons.add_location_alt_outlined),label:Text(S.t('point.poi'))),
            if(a.bearing!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(a.bearing),icon:const Icon(Icons.track_changes),label:Text(S.t('converter.bearing'))),
            if(a.order!=null)OutlinedButton.icon(style:OutlinedButton.styleFrom(shape:const StadiumBorder()),
              onPressed:()=>_act(a.order),icon:const Icon(Icons.flag_outlined),label:Text(S.t('point.order'))),
          ]),
        ],
        if(_history.isNotEmpty)...[
          const SizedBox(height:20),
          Row(children:[Expanded(child:Text(S.t('converter.history'),style:t.textTheme.titleSmall)),
            OutlinedButton(onPressed:(){setState(()=>_history=[]);unawaited(widget.store?.setPreference(_historyKey,null));},child:Text(S.t('converter.historyClear')))]),
          for(final h in _history)ListTile(dense:true,leading:const Icon(Icons.history),
            title:Text('${h['label']??''}',maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle:Text(formatDd(LatLng((h['lat'] as num).toDouble(),(h['lon'] as num).toDouble()))),
            onTap:()=>setState((){_source=ConverterSource.input;_gps?.cancel();_gps=null;
              _text.text=formatDd(LatLng((h['lat'] as num).toDouble(),(h['lon'] as num).toDouble()),decimal:'.');_fields=false;})),
        ],
      ]),
    );
  }
}
