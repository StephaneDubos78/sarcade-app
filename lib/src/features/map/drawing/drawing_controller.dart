import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'geometry.dart';
import 'import_formats.dart';
import 'map_feature.dart';

/// Operational palette, ARGB. Red first: it is the default for SAR annotations.
/// Fixed palette, readable on the OSM, IGN and satellite maps: red, orange,
/// yellow, green, blue, purple, black, white (note « Couleur de dessin par
/// défaut »).
/// 16 well distinct colours (« Couleurs des opérateurs », 28 Oct 2026: the
/// ADRASEC has 20 members), two rows of 8 in the profile.
const drawingPalette=<int>[0xFFE53935,0xFFFB8C00,0xFFFDD835,0xFFC0CA33,0xFF43A047,0xFF00897B,0xFF00ACC1,0xFF039BE5,
  0xFF1E88E5,0xFF3949AB,0xFF8E24AA,0xFFD81B60,0xFF6D4C41,0xFF757575,0xFF212121,0xFFFFFFFF];

/// Colour of new drawings chosen in the profile (any colour, « Autre
/// couleur »); red when none.
int defaultDrawColor(int? chosen)=>chosen??drawingPalette.first;

/// Colour given to an operator without a chosen one: the palette colour
/// the least used by the others in the event (white and black left out).
int autoColor(Iterable<int> usedByOthers){
  final candidates=drawingPalette.where((c)=>c!=0xFFFFFFFF&&c!=0xFF212121).toList();
  final count={for(final c in candidates)c:0};
  for(final c in usedByOthers){if(count.containsKey(c))count[c]=count[c]!+1;}
  final least=count.values.reduce((a,b)=>a<b?a:b);
  return candidates.firstWhere((c)=>count[c]==least);
}
const drawingWidths=<double>[2,4,7];
/// Transparency choices of a drawn object (selection bar).
const drawingOpacities=<double>[1,0.75,0.5,0.25];

/// One undoable action: the state of each touched object before and after.
/// A null value means the object did not exist. Undo only touches these
/// objects, so it never reverts what other operators changed (ADR-001).
class _Step {
  final Map<String,MapFeature?> before, after;
  _Step(this.before,this.after);
}

/// State of the PowerPoint-like drawing tools: active tool, shape being drawn,
/// selection, styles and undo/redo. Pure logic, no widgets, so it is unit tested.
///
/// Local changes are reported through [onChanged] and [onDeleted] so the page
/// can store and synchronise them. Changes coming from the server go through
/// [applyRemote] and [removeRemote], which do not report back and are not undoable.
class DrawingController extends ChangeNotifier {
  final String eventId, actorId;
  final void Function(MapFeature feature,{required bool isNew})? onChanged;
  final void Function(MapFeature feature)? onDeleted;
  DrawingController({required this.eventId,required this.actorId,Iterable<MapFeature> initial=const [],this.onChanged,this.onDeleted}){
    for(final f in initial){_features[f.id]=f;}
  }

  final _uuid=const Uuid();
  final Map<String,MapFeature> _features={};
  final List<_Step> _undo=[], _redo=[];
  static const _historyLimit=50;
  Map<String,MapFeature?>? _editBefore;

  FeatureKind? _tool;
  final List<LatLng> _draft=[];
  /// Selected objects, in the order of selection (card « Dessin, sélection
  /// multiple », 29 Oct 2026): one object for the usual selection bar,
  /// several for the common action bar.
  final List<String> _selection=[];
  /// Phone: « Sélection » button of the drawing bar, a drag draws the
  /// selection rectangle and a touch adds or removes an object.
  bool selectMode=false;
  /// Objects that can join a multiple selection: one's own, or every one
  /// for the PCO (proposal 6). Set by the map page.
  bool Function(MapFeature f) canSelect=_any;
  static bool _any(MapFeature _)=>true;
  /// Change of several objects at once, carried with each synchronised
  /// operation so that the server writes one logbook line (proposal 5).
  ({String id,int n,String action})? _group;
  Map<String,dynamic>? get groupJson{final g=_group;return g==null?null:{'id':g.id,'n':g.n,'action':g.action};}
  int color=drawingPalette.first;
  double strokeWidth=drawingWidths[1];

  FeatureKind? get tool=>_tool;
  List<LatLng> get draft=>List.unmodifiable(_draft);
  List<MapFeature> get features=>_features.values.toList()..sort((a,b)=>a.updatedAt.compareTo(b.updatedAt));
  MapFeature? feature(String id)=>_features[id];
  /// The selected object when exactly one is selected.
  MapFeature? get selected=>_selection.length==1?_features[_selection.first]:null;
  /// Every selected object.
  List<MapFeature> get selection=>[for(final id in _selection)?_features[id]];
  bool get hasSelection=>_selection.isNotEmpty;
  bool get isMulti=>_selection.length>1;
  bool isSelected(String id)=>_selection.contains(id);
  bool get canUndo=>_undo.isNotEmpty;
  bool get canRedo=>_redo.isNotEmpty;
  bool get isDrawing=>_tool!=null;

  /// The map should not pan while a shape is selected or freehand is active,
  /// so handle drags and freehand strokes are not stolen by the map.
  bool get locksMapDrag=>_selection.isNotEmpty||selectMode||_tool==FeatureKind.freehand;

  /// Length or area of the shape being drawn, for the live status line.
  String? get draftMeasure{
    final t=_tool;
    if(t==null||_draft.isEmpty)return null;
    if(t==FeatureKind.zone&&_draft.length>=3)return formatArea(polygonArea(_draft));
    if(t.isLinear&&_draft.length>=2)return formatDistance(pathLength(_draft));
    return null;
  }

  bool get canFinish=>_tool!=null&&_tool!.isMultiVertex&&_draft.length>=_tool!.minPoints;

  void selectTool(FeatureKind? kind){
    _tool=kind;_draft.clear();_selection.clear();if(kind!=null)selectMode=false;
    notifyListeners();
  }

  /// Handles a tap on the map while a tool is active. Returns the created
  /// feature when the tap completes one (point, text, circle, rectangle).
  MapFeature? tapAt(LatLng p,{String label=''}){
    final t=_tool;
    if(t==null)return null;
    switch(t){
      case FeatureKind.point:
      case FeatureKind.text:
        return _commit(t,[p],label:label);
      case FeatureKind.circle:
        if(_draft.isEmpty){_draft.add(p);notifyListeners();return null;}
        final r=distanceM(_draft.first,p);
        if(r<1){return null;}
        return _commit(t,[_draft.first],radiusM:r);
      case FeatureKind.rectangle:
      case FeatureKind.arrow:
        if(_draft.isEmpty){_draft.add(p);notifyListeners();return null;}
        if(_draft.first==p)return null;
        return _commit(t,[_draft.first,p]);
      case FeatureKind.freehand:
        return null;
      default:
        _draft.add(p);notifyListeners();return null;
    }
  }

  void undoLastVertex(){if(_draft.isNotEmpty){_draft.removeLast();notifyListeners();}}

  /// Finishes a multi-vertex shape (line, arrow, zone, measure).
  MapFeature? finish(){
    final t=_tool;
    if(!canFinish||t==null)return null;
    return _commit(t,List.of(_draft));
  }

  void cancelDraft(){_draft.clear();notifyListeners();}

  /// Commits a freehand stroke captured by the gesture overlay.
  MapFeature? commitFreehand(List<LatLng> stroke){
    if(stroke.length<2)return null;
    return _commit(FeatureKind.freehand,stroke);
  }

  MapFeature _commit(FeatureKind kind,List<LatLng> points,{double? radiusM,String label=''}){
    final f=MapFeature(
      // UUID v7: time-ordered, recommended by ADR-001 for new object types.
      id:_uuid.v7(),eventId:eventId,kind:kind,points:points,radiusM:radiusM,
      color:color,strokeWidth:strokeWidth,label:label,createdBy:actorId,updatedBy:actorId,updatedAt:DateTime.now().toUtc(),
    );
    _draft.clear();
    // Like PowerPoint: the new shape is selected so it can be styled at once,
    // and the tool is released so the next tap selects instead of drawing.
    _tool=null;_selection..clear()..add(f.id);
    _record({f.id:null},{f.id:f});
    _put(f,isNew:true);
    notifyListeners();
    return f;
  }

  /// Adds shapes read from a file as new objects, synchronised like drawn ones.
  /// The whole import is one undo step. Returns the created objects.
  List<MapFeature> importShapes(List<ImportedShape> shapes){
    if(shapes.isEmpty)return const [];
    final now=DateTime.now().toUtc();
    final created=<MapFeature>[
      for(final s in shapes)MapFeature(
        id:_uuid.v7(),eventId:eventId,kind:s.kind,points:s.points,radiusM:s.radiusM,
        color:s.color??color,strokeWidth:strokeWidth,label:s.label,
        createdBy:actorId,updatedBy:actorId,updatedAt:now,
      ),
    ];
    _tool=null;_draft.clear();_selection.clear();
    _record({for(final f in created)f.id:null},{for(final f in created)f.id:f});
    for(final f in created){_put(f,isNew:true);}
    notifyListeners();
    return created;
  }

  void select(String? id){
    if(id!=null&&!_features.containsKey(id))return;
    _selection.clear();if(id!=null)_selection.add(id);
    notifyListeners();
  }

  /// Ctrl / Maj + clic, or a touch in « Sélection »: adds or removes one object.
  void toggle(String id){
    final f=_features[id]; if(f==null)return;
    if(_selection.contains(id)){_selection.remove(id);}
    else if(canSelect(f)||_selection.isEmpty){_selection.add(id);}
    notifyListeners();
  }

  /// Objects touched by the selection rectangle join the selection.
  void addToSelection(Iterable<String> ids){
    for(final id in ids){final f=_features[id];if(f!=null&&canSelect(f)&&!_selection.contains(id))_selection.add(id);}
    notifyListeners();
  }

  void setSelectMode(bool on){selectMode=on;if(on){_tool=null;_draft.clear();}notifyListeners();}
  /// Selection out of the drawing bar (card « Sélection sortie de la barre de
  /// dessin », 30 Oct 2026, 17 h 36): a long press on an object starts it
  /// with that object, « Sélectionner une zone » without any.
  void startSelection([String? id]){
    selectMode=true;_tool=null;_draft.clear();
    if(id!=null&&_features.containsKey(id)&&!_selection.contains(id))_selection.add(id);
    notifyListeners();
  }
  /// ✕, Échap, a touch on the empty map, closing the drawing bar or opening
  /// another panel: nothing selected, no tool, the map moves again.
  void endSelection(){selectMode=false;_selection.clear();if(_tool!=null){_tool=null;_draft.clear();}notifyListeners();}

  void _grouped(String action,int n,void Function() run){
    _group=n>1?(id:_uuid.v4(),n:n,action:action):null;
    try{run();}finally{_group=null;}
  }

  // Drag gestures: call beginEdit once at the start, then the move/update
  // methods for every frame, then endEdit, so one drag is one undo step and
  // one synchronised change.
  void beginEdit(){final all=selection;_editBefore=all.isEmpty?null:{for(final f in all)f.id:f};}

  void moveSelected(double dLat,double dLon){_mutateSelected((f)=>f.translated(dLat,dLon));}

  void moveVertex(int index,LatLng to){
    _mutateSelected((f){
      final pts=List.of(f.points);
      if(index<0||index>=pts.length)return f;
      pts[index]=to;
      return f.copyWith(points:pts);
    });
  }

  /// Point in the middle of a side dragged: a new vertex there (proposal 4).
  void insertVertex(int index,LatLng p){
    _mutateSelected((f){
      final pts=List.of(f.points);
      if(index<0||index>pts.length)return f;
      pts.insert(index,p);
      return f.copyWith(points:pts);
    });
  }

  void setRadius(double r){_mutateSelected((f)=>f.copyWith(radiusM:r<1?1:r));}

  void endEdit(){
    final before=_editBefore;
    _editBefore=null;
    if(before==null)return;
    final changed=<String,MapFeature>{};
    for(final id in before.keys){final f=_features[id];if(f!=null&&!identical(before[id],f))changed[id]=_stamp(f);}
    if(changed.isEmpty)return;
    _features.addAll(changed);
    _record({for(final id in changed.keys)id:before[id]},changed);
    _grouped('move',changed.length,(){for(final f in changed.values){onChanged?.call(f,isNew:false);}});
    notifyListeners();
  }

  void setColor(int c){color=c;_changeSelected((f)=>f.copyWith(color:c));}
  void setStrokeWidth(double w){strokeWidth=w;_changeSelected((f)=>f.copyWith(strokeWidth:w));}
  void setLabel(String label){_changeSelected((f)=>f.copyWith(label:label.trim()));}
  void toggleGeofence(){_changeSelected((f)=>f.copyWith(geofence:!f.geofence));}
  void setOpacity(double o){_changeSelected((f)=>f.copyWith(opacity:o.clamp(0.1,1.0)));}
  /// Font size of the selected Texte objects.
  void setFontSize(double size){_changeSelected((f)=>f.kind==FeatureKind.text?f.copyWith(fontSize:size.clamp(8.0,72.0)):f);}

  /// Deletes every selected object: one undo step.
  void deleteSelected(){
    final all=selection;
    if(all.isEmpty)return;
    _selection.clear();
    _record({for(final f in all)f.id:f},{for(final f in all)f.id:null});
    _grouped('delete',all.length,(){for(final f in all){_remove(f.id);}});
    notifyListeners();
  }

  /// Copy shifted slightly north-east, selected, like Ctrl+D in PowerPoint.
  MapFeature? duplicateSelected({double offsetDeg=0.0005}){
    final all=selection;
    if(all.isEmpty)return null;
    final copies=[for(final f in all)_stamp(f.translated(offsetDeg,offsetDeg).copyWith(id:_uuid.v7()))];
    _selection..clear()..addAll(copies.map((c)=>c.id));
    _record({for(final c in copies)c.id:null},{for(final c in copies)c.id:c});
    _grouped('duplicate',copies.length,(){for(final c in copies){_put(c,isNew:true);}});
    notifyListeners();
    return copies.first;
  }

  void undo(){
    if(_undo.isEmpty)return;
    final step=_undo.removeLast();
    _redo.add(step);
    _grouped('undo',step.before.length,()=>_apply(step.before));
  }

  void redo(){
    if(_redo.isEmpty)return;
    final step=_redo.removeLast();
    _undo.add(step);
    _grouped('redo',step.after.length,()=>_apply(step.after));
  }

  /// Applies a server state. Ignored when it is not newer than the local copy,
  /// so a late echo cannot roll back a more recent local edit.
  void applyRemote(MapFeature f){
    final local=_features[f.id];
    if(local!=null&&!_isNewer(f,local))return;
    _features[f.id]=f;
    notifyListeners();
  }

  /// Applies a server deletion, unless the local copy was changed after it.
  void removeRemote(String id,{DateTime? at,String? by}){
    final local=_features[id];
    if(local==null)return;
    if(at!=null){
      final c=local.updatedAt.compareTo(at);
      if(c>0||(c==0&&(local.updatedBy??'').compareTo(by??'')>0))return;
    }
    _features.remove(id);
    _selection.remove(id);
    notifyListeners();
  }

  bool _isNewer(MapFeature a,MapFeature b){
    final c=a.updatedAt.compareTo(b.updatedAt);
    if(c!=0)return c>0;
    return (a.updatedBy??'').compareTo(b.updatedBy??'')>=0;
  }

  /// Restores the given states. Restored objects get a fresh timestamp so the
  /// server accepts them as the newest change (an undo is a new change).
  void _apply(Map<String,MapFeature?> states){
    for(final e in states.entries){
      final target=e.value;
      if(target==null){
        _remove(e.key);
      }else{
        final existed=_features.containsKey(e.key);
        _put(_stamp(target),isNew:!existed);
      }
    }
    _selection.removeWhere((id)=>!_features.containsKey(id));
    notifyListeners();
  }

  MapFeature _stamp(MapFeature f)=>f.copyWith(updatedBy:actorId,updatedAt:DateTime.now().toUtc());

  void _put(MapFeature f,{required bool isNew}){
    _features[f.id]=f;
    onChanged?.call(f,isNew:isNew);
  }

  void _remove(String id){
    final f=_features.remove(id);
    if(f!=null)onDeleted?.call(f);
  }

  void _record(Map<String,MapFeature?> before,Map<String,MapFeature?> after){
    _undo.add(_Step(before,after));
    if(_undo.length>_historyLimit)_undo.removeAt(0);
    _redo.clear();
  }

  /// One-shot change of the selection (style, label): one undo step.
  void _changeSelected(MapFeature Function(MapFeature) change){
    final all=selection;
    if(all.isEmpty){notifyListeners();return;}
    final next={for(final f in all)f.id:_stamp(change(f))};
    _record({for(final f in all)f.id:f},next);
    _grouped('style',all.length,(){for(final f in next.values){_put(f,isNew:false);}});
    notifyListeners();
  }

  /// Live change during a drag: shown at once, recorded and synced on endEdit.
  void _mutateSelected(MapFeature Function(MapFeature) change){
    final all=selection;
    if(all.isEmpty)return;
    for(final f in all){_features[f.id]=change(f);}
    notifyListeners();
  }
}
