import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import 'geometry.dart';
import 'map_feature.dart';

/// Operational palette, ARGB. Red first: it is the default for SAR annotations.
const drawingPalette=<int>[0xFFE53935,0xFFFB8C00,0xFFFDD835,0xFF43A047,0xFF1E88E5,0xFF8E24AA,0xFF212121];
const drawingWidths=<double>[2,4,7];

/// State of the PowerPoint-like drawing tools: active tool, shape being drawn,
/// selection, styles and undo/redo. Pure logic, no widgets, so it is unit tested.
class DrawingController extends ChangeNotifier {
  final String eventId, actorId;
  final void Function(MapFeature)? onSaved;
  final void Function(String id)? onDeleted;
  DrawingController({required this.eventId,required this.actorId,Iterable<MapFeature> initial=const [],this.onSaved,this.onDeleted}){
    for(final f in initial){_features[f.id]=f;}
  }

  final _uuid=const Uuid();
  final Map<String,MapFeature> _features={};
  final List<Map<String,MapFeature>> _undo=[], _redo=[];
  static const _historyLimit=50;

  FeatureKind? _tool;
  final List<LatLng> _draft=[];
  String? _selectedId;
  int color=drawingPalette.first;
  double strokeWidth=drawingWidths[1];

  FeatureKind? get tool=>_tool;
  List<LatLng> get draft=>List.unmodifiable(_draft);
  List<MapFeature> get features=>_features.values.toList()..sort((a,b)=>a.updatedAt.compareTo(b.updatedAt));
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
    _snapshot();
    final f=MapFeature(
      id:_uuid.v4(),eventId:eventId,kind:kind,points:points,radiusM:radiusM,
      color:color,strokeWidth:strokeWidth,label:label,createdBy:actorId,updatedAt:DateTime.now().toUtc(),
    );
    _features[f.id]=f;
    _draft.clear();
    // Like PowerPoint: the new shape is selected so it can be styled at once,
    // and the tool is released so the next tap selects instead of drawing.
    _tool=null;_selectedId=f.id;
    onSaved?.call(f);
    notifyListeners();
    return f;
  }

  void select(String? id){
    if(id!=null&&!_features.containsKey(id))return;
    _selectedId=id;notifyListeners();
  }

  // Drag gestures: call beginEdit once at the start, then the move/update
  // methods for every frame, so one drag is one undo step.
  void beginEdit(){_snapshot();}

  void moveSelected(double dLat,double dLon){_replaceSelected((f)=>f.translated(dLat,dLon),save:false);}

  void moveVertex(int index,LatLng to){
    _replaceSelected((f){
      final pts=List.of(f.points);
      if(index<0||index>=pts.length)return f;
      pts[index]=to;
      return f.copyWith(points:pts);
    },save:false);
  }

  void setRadius(double r){_replaceSelected((f)=>f.copyWith(radiusM:r<1?1:r),save:false);}

  /// Persists the selected feature at the end of a drag.
  void endEdit(){final f=selected;if(f!=null)onSaved?.call(f);}

  void setColor(int c){color=c;if(selected!=null){_snapshot();_replaceSelected((f)=>f.copyWith(color:c));}else{notifyListeners();}}
  void setStrokeWidth(double w){strokeWidth=w;if(selected!=null){_snapshot();_replaceSelected((f)=>f.copyWith(strokeWidth:w));}else{notifyListeners();}}
  void setLabel(String label){if(selected!=null){_snapshot();_replaceSelected((f)=>f.copyWith(label:label.trim()));}}

  void deleteSelected(){
    final id=_selectedId;
    if(id==null)return;
    _snapshot();
    _features.remove(id);_selectedId=null;
    onDeleted?.call(id);
    notifyListeners();
  }

  /// Copy shifted slightly north-east, selected, like Ctrl+D in PowerPoint.
  MapFeature? duplicateSelected({double offsetDeg=0.0005}){
    final f=selected;
    if(f==null)return null;
    _snapshot();
    final copy=f.translated(offsetDeg,offsetDeg).copyWith(id:_uuid.v4());
    _features[copy.id]=copy;_selectedId=copy.id;
    onSaved?.call(copy);
    notifyListeners();
    return copy;
  }

  void undo(){
    if(_undo.isEmpty)return;
    _redo.add(Map.of(_features));
    _restore(_undo.removeLast());
  }

  void redo(){
    if(_redo.isEmpty)return;
    _undo.add(Map.of(_features));
    _restore(_redo.removeLast());
  }

  void _restore(Map<String,MapFeature> state){
    final removed=_features.keys.where((k)=>!state.containsKey(k)).toList();
    final changed=state.values.where((f)=>!identical(_features[f.id],f)).toList();
    _features..clear()..addAll(state);
    if(_selectedId!=null&&!_features.containsKey(_selectedId))_selectedId=null;
    for(final id in removed){onDeleted?.call(id);}
    for(final f in changed){onSaved?.call(f);}
    notifyListeners();
  }

  void _snapshot(){
    _undo.add(Map.of(_features));
    if(_undo.length>_historyLimit)_undo.removeAt(0);
    _redo.clear();
  }

  void _replaceSelected(MapFeature Function(MapFeature) change,{bool save=true}){
    final f=selected;
    if(f==null)return;
    final next=change(f);
    _features[f.id]=next;
    if(save)onSaved?.call(next);
    notifyListeners();
  }
}
