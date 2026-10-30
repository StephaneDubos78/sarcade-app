import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/strings.dart';
import '../dictation/dictation_button.dart';
import 'map_search.dart';

/// Search field at the top of the map, with its microphone and the result
/// list below it. Local results show at once; addresses come from the
/// server a moment later (none offline).
class MapSearchBar extends StatefulWidget {
  final Iterable<Searchable> Function() items;
  final Future<List<SearchResult>> Function(String query,LatLng? near) addresses;
  final LatLng? Function() near;
  final void Function(SearchResult) onPick;
  const MapSearchBar({super.key,required this.items,required this.addresses,required this.near,required this.onPick});
  @override State<MapSearchBar> createState()=>_MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final _ctrl=TextEditingController(); final _focus=FocusNode();
  List<SearchResult> _local=const [], _remote=const [];
  bool _loading=false, _addressesOff=false; Timer? _debounce; int _run=0;

  @override void dispose(){_debounce?.cancel();_ctrl.dispose();_focus.dispose();super.dispose();}

  void _changed(){
    final q=_ctrl.text;
    setState((){_local=searchLocal(q,widget.items());if(q.trim().length<3){_remote=const [];_addressesOff=false;}});
    _debounce?.cancel();
    if(q.trim().length<3)return;
    _debounce=Timer(const Duration(milliseconds:400),()=>_searchAddresses(q));
  }

  Future<void> _searchAddresses(String q) async {
    final run=++_run;
    setState(()=>_loading=true);
    try{
      final r=await widget.addresses(q.trim(),widget.near());
      if(mounted&&run==_run)setState((){_remote=r;_addressesOff=false;});
    }catch(_){
      if(mounted&&run==_run)setState((){_remote=const [];_addressesOff=true;});
    }finally{
      if(mounted&&run==_run)setState(()=>_loading=false);
    }
  }

  void _pick(SearchResult r){
    _focus.unfocus();
    setState((){_local=const [];_remote=const [];});
    widget.onPick(r);
  }

  void _clear(){_ctrl.clear();_debounce?.cancel();_run++;setState((){_local=const [];_remote=const [];_loading=false;_addressesOff=false;});}

  static IconData _icon(SearchKind k)=>switch(k){
    SearchKind.coordinates=>Icons.pin_drop_outlined, SearchKind.operator=>Icons.person_pin_circle_outlined,
    SearchKind.reference=>Icons.cell_tower, SearchKind.poi=>Icons.place_outlined,
    SearchKind.drawing=>Icons.draw_outlined, SearchKind.address=>Icons.home_work_outlined};

  @override
  Widget build(BuildContext context){
    final results=[..._local,..._remote];
    final open=_ctrl.text.trim().length>=2&&_focus.hasFocus;
    // Little room (a panel is open beside the map, revue d'ergonomie n° 53):
    // a round magnifier rather than a field cut to « R… ».
    return LayoutBuilder(builder:(context,box){
      if(searchAsIcon(box.maxWidth,typing:_focus.hasFocus||_ctrl.text.isNotEmpty||_wide)){
        return Material(elevation:3,shape:const CircleBorder(),child:IconButton(key:const ValueKey('search-icon'),tooltip:S.t('search.hint'),
          icon:const Icon(Icons.search),onPressed:(){setState(()=>_wide=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_focus.requestFocus();});}));
      }
      return _bar(results,open);
    });
  }

  /// Opened from the magnifier: the field stays until it loses the focus.
  bool _wide=false;
  @override void initState(){super.initState();_focus.addListener((){if(!_focus.hasFocus&&_ctrl.text.isEmpty&&_wide&&mounted)setState(()=>_wide=false);});}

  Widget _bar(List<SearchResult> results,bool open){
    return ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Material(elevation:3,borderRadius:BorderRadius.circular(28),child:Padding(padding:const EdgeInsets.only(left:14),child:Row(children:[
        const Icon(Icons.search),
        const SizedBox(width:8),
        Expanded(child:TextField(controller:_ctrl,focusNode:_focus,onChanged:(_)=>_changed(),
          onTap:()=>setState((){}),textInputAction:TextInputAction.search,
          onSubmitted:(_){if(results.isNotEmpty)_pick(results.first);},
          decoration:InputDecoration(hintText:S.t('search.hint'),border:InputBorder.none,isDense:true))),
        if(_loading)const Padding(padding:EdgeInsets.all(8),child:SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))),
        if(_ctrl.text.isNotEmpty)IconButton(tooltip:S.t('search.clear'),onPressed:_clear,icon:const Icon(Icons.close)),
        DictationButton(controller:_ctrl,onChanged:(){_focus.requestFocus();_changed();}),
      ]))),
      if(open)Padding(padding:const EdgeInsets.only(top:6),child:Material(elevation:3,borderRadius:BorderRadius.circular(12),clipBehavior:Clip.antiAlias,
        child:ConstrainedBox(constraints:const BoxConstraints(maxHeight:360),child:ListView(shrinkWrap:true,padding:EdgeInsets.zero,children:[
          for(final r in results)ListTile(dense:true,leading:Icon(_icon(r.kind)),
            title:Text(r.title,maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle:Text([S.t('search.kind.${r.kind.name}'),if(r.subtitle.isNotEmpty)r.subtitle].join(' · '),maxLines:1,overflow:TextOverflow.ellipsis),
            onTap:()=>_pick(r)),
          if(results.isEmpty&&!_loading)ListTile(dense:true,title:Text(S.t('search.none'))),
          if(_addressesOff)ListTile(dense:true,leading:const Icon(Icons.cloud_off,size:18),title:Text(S.t('search.addressesOff'))),
        ])))),
    ]));
  }
}

/// Below this width, the search shows as a magnifier (unless in use).
const searchIconBelow=150.0;
bool searchAsIcon(double width,{required bool typing})=>!typing&&width<searchIconBelow;
