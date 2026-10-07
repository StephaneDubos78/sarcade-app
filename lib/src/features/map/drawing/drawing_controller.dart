import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'geometry.dart';
import 'import_formats.dart';
import 'map_feature.dart';

/// Operational palette, ARGB. Red first: it is the default for SAR annotations.
const drawingPalette=<int>[0xFFE53935,0xFFFB8C00,0xFFFDD835,0xFF43A047,0xFF1E88E5,0xFF8E24AA,0xFF212121];
const drawingWidths=<double>[2,4,7];

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
  String? _selectedId;
  int color=drawingPalette.first;
  double strokeWidth=drawingWidths[1];

  FeatureKind? get tool=>_tool;
  List<LatLng> get draft=>List.unmodifiable(_draft);
  List<MapFeature> get features=>_features.values.toList()..sort((a,b)=>a.updatedAt.compareTo(b.updatedAt));
  MapFeature? feature(String id)=>_features[id];
  MapFeature? get selected=>_selectedId==null?null:_features[_selectedId];
  bool get canUndo=>_undo.isNotEmpty;
  bool get canRedo=>_redo.isNotEmpty;
  bool get isDrawing=>_tool!=null;

  /// The map should not pan while a shape is selected or freehand is active,
  /// so handle drags and freehand strokes are not stolen by the map.
  bool get locksMapDrag=>_selectedId!=null||_tool==FeatureKind.freehand;

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
    _tool=kind;_draft.clear();_selectedId=null;
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
    _tool=null;_selectedId=f.id;
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
    _tool=null;_draft.clear();_selectedId=null;
    _record({for(final f in created)f.id:null},{for(final f in created)f.id:f});
    for(final f in created){_put(f,isNew:true);}
    notifyListeners();
    return created;
  }

  void select(String? id){
    if(id!=null&&!_features.containsKey(id))return;
    _selectedId=id;notifyListeners();
  }

  // Drag gestures: call beginEdit once at the start, then the move/update
  // methods for every frame, then endEdit, so one drag is one undo step and
  // one synchronised change.
  void beginEdit(){final f=selected;_editBefore=f==null?null:{f.id:f};}

  void moveSelected(double dLat,double dLon){_mutateSelected((f)=>f.translated(dLat,dLon));}

  void moveVertex(int index,LatLng to){
    _mutateSelected((f){
      final pts=List.of(f.points);
      if(index<0||index>=pts.length)return f;
      pts[index]=to;
      return f.copyWith(points:pts);
    });
  }

  void setRadius(double r){_mutateSelected((f)=>f.copyWith(radiusM:r<1?1:r));}

  void endEdit(){
    final before=_editBefore, f=selected;
    _editBefore=null;
    if(before==null||f==null||identical(before[f.id],f))return;
    final stamped=_stamp(f);
    _features[f.id]=stamped;
    _record(before,{f.id:stamped});
    onChanged?.call(stamped,isNew:false);
    notifyListeners();
  }

  void setColor(int c){color=c;_changeSelected((f)=>f.copyWith(color:c));}
  void setStrokeWidth(double w){strokeWidth=w;_changeSelected((f)=>f.copyWith(strokeWidth:w));}
  void setLabel(String label){_changeSelected((f)=>f.copyWith(label:label.trim()));}

  void deleteSelected(){
    final f=selected;
    if(f==null)return;
    _selectedId=null;
    _record({f.id:f},{f.id:null});
    _remove(f.id);
    notifyListeners();
  }

  /// Copy shifted slightly north-east, selected, like Ctrl+D in PowerPoint.
  MapFeature? duplicateSelected({double offsetDeg=0.0005}){
    final f=selected;
    if(f==null)return null;
    final copy=_stamp(f.translated(offsetDeg,offsetDeg).copyWith(id:_uuid.v7()));
    _selectedId=copy.id;
    _record({copy.id:null},{copy.id:copy});
    _put(copy,isNew:true);
    notifyListeners();
    return copy;
  }

  void undo(){
    if(_undo.isEmpty)return;
    final step=_undo.removeLast();
    _redo.add(step);
    _apply(step.before);
  }

  void redo(){
    if(_redo.isEmpty)return;
    final step=_redo.removeLast();
    _undo.add(step);
    _apply(step.after);
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
    if(_selectedId==id)_selectedId=null;
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
    if(_selectedId!=null&&!_features.containsKey(_selectedId))_selectedId=null;
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
    final f=selected;
    if(f==null){notifyListeners();return;}
    final next=_stamp(change(f));
    _record({f.id:f},{f.id:next});
    _put(next,isNew:false);
    notifyListeners();
  }

  /// Live change during a drag: shown at once, recorded and synced on endEdit.
  void _mutateSelected(MapFeature Function(MapFeature) change){
    final f=selected;
    if(f==null)return;
    _features[f.id]=change(f);
    notifyListeners();
  }
}
