import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';
import 'package:sarcade_app/src/features/map/drawing/geometry.dart';
import 'package:sarcade_app/src/features/map/drawing/hit_test.dart';
import 'package:sarcade_app/src/features/map/drawing/map_feature.dart';

void main(){
  group('geometry',(){
    test('one degree of latitude is about 111.2 km',(){
      expect(distanceM(const LatLng(48,2),const LatLng(49,2)),closeTo(111195,50));
    });

    test('bearing and destination are consistent',(){
      const a=LatLng(48.77,2.03);
      final b=destination(a,1000,90);
      expect(distanceM(a,b),closeTo(1000,0.5));
      expect(bearingDeg(a,b),closeTo(90,0.1));
    });

    test('a 1 km square has an area of about 1 km2',(){
      const sw=LatLng(48.7,2.0);
      final se=destination(sw,1000,90), nw=destination(sw,1000,0);
      final ring=rectangleCorners(sw,LatLng(nw.latitude,se.longitude));
      expect(polygonArea(ring),closeTo(1e6,1e4));
    });

    test('French formatting',(){
      expect(formatDistance(850),'850 m');
      expect(formatDistance(1250),'1,25 km');
      expect(formatDistance(12400),'12,4 km');
      expect(formatArea(850),'850 m²');
      expect(formatArea(24000),'2,40 ha');
      expect(formatArea(3100000),'3,10 km²');
    });
  });

  group('MapFeature',(){
    MapFeature feature(FeatureKind kind,List<LatLng> pts,{double? radius})=>MapFeature(id:'f1',eventId:'e1',kind:kind,points:pts,radiusM:radius,color:0xFFE53935,strokeWidth:4,label:'Secteur A',updatedAt:DateTime.utc(2026,10,7));

    test('JSON round trip keeps geometry and style',(){
      final f=feature(FeatureKind.zone,const [LatLng(48.7,2.0),LatLng(48.71,2.0),LatLng(48.71,2.01)]);
      final back=MapFeature.fromJson(f.toJson());
      expect(back.kind,FeatureKind.zone);
      expect(back.points,f.points);
      expect(back.color,f.color);
      expect(back.label,'Secteur A');
    });

    test('zone exports as a closed GeoJSON polygon in lon/lat order',(){
      final f=feature(FeatureKind.zone,const [LatLng(48.7,2.0),LatLng(48.71,2.0),LatLng(48.71,2.01)]);
      final g=f.toGeoJson();
      final ring=(g['geometry'] as Map)['coordinates'][0] as List;
      expect((g['geometry'] as Map)['type'],'Polygon');
      expect(ring.first,[2.0,48.7]);
      expect(ring.last,ring.first);
      expect(ring.length,4);
      expect((g['properties'] as Map)['name'],'Secteur A');
      expect((g['properties'] as Map)['stroke'],'#e53935');
    });

    test('circle exports as a point with its radius',(){
      final g=feature(FeatureKind.circle,const [LatLng(48.7,2.0)],radius:250).toGeoJson();
      expect((g['geometry'] as Map)['type'],'Point');
      expect((g['properties'] as Map)['radius_m'],250);
    });

    test('measure exports its length',(){
      final g=feature(FeatureKind.measure,const [LatLng(48,2),LatLng(49,2)]).toGeoJson();
      expect((g['geometry'] as Map)['type'],'LineString');
      expect((g['properties'] as Map)['length_m'],closeTo(111195,50));
    });
  });

  group('hitTest',(){
    // 1 degree = 1000 px, north up: enough to reason in pixels.
    Offset project(LatLng p)=>Offset(p.longitude*1000,-p.latitude*1000);
    MapFeature f(String id,FeatureKind kind,List<LatLng> pts,{DateTime? at})=>MapFeature(id:id,eventId:'e',kind:kind,points:pts,color:0,strokeWidth:4,updatedAt:at??DateTime.utc(2026));

    test('selects a line within the finger tolerance',(){
      final line=f('l',FeatureKind.line,const [LatLng(0,0),LatLng(0,1)]);
      expect(hitTest([line],const Offset(500,10),project)?.id,'l');
      expect(hitTest([line],const Offset(500,40),project),isNull);
    });

    test('selects inside a zone, and a line on top of it wins',(){
      final zone=f('z',FeatureKind.zone,const [LatLng(0,0),LatLng(0,1),LatLng(-1,1),LatLng(-1,0)]);
      final line=f('l',FeatureKind.line,const [LatLng(-0.5,0.2),LatLng(-0.5,0.8)]);
      expect(hitTest([zone],const Offset(500,500),project)?.id,'z');
      expect(hitTest([zone,line],const Offset(500,505),project)?.id,'l');
    });

    test('circle uses its radius in pixels',(){
      final c=MapFeature(id:'c',eventId:'e',kind:FeatureKind.circle,points:const [LatLng(0,0)],radiusM:1,color:0,strokeWidth:2,updatedAt:DateTime.utc(2026));
      expect(hitTest([c],const Offset(80,0),project,radiusPx:(_)=>100)?.id,'c');
      expect(hitTest([c],const Offset(150,0),project,radiusPx:(_)=>100),isNull);
    });
  });

  group('DrawingController',(){
    test('zone: vertices, live area, finish selects the new shape',(){
      final saved=<MapFeature>[];
      final c=DrawingController(eventId:'e',actorId:'TERRAIN-01',onChanged:(f,{required isNew}){if(isNew)saved.add(f);});
      c.selectTool(FeatureKind.zone);
      c.tapAt(const LatLng(48.7,2.0));
      c.tapAt(const LatLng(48.71,2.0));
      expect(c.canFinish,isFalse);
      c.tapAt(const LatLng(48.71,2.01));
      expect(c.canFinish,isTrue);
      expect(c.draftMeasure,endsWith('ha'));
      final f=c.finish()!;
      expect(f.kind,FeatureKind.zone);
      expect(f.createdBy,'TERRAIN-01');
      expect(c.tool,isNull);
      expect(c.selected?.id,f.id);
      expect(saved.single.id,f.id);
    });

    test('circle takes a centre then an edge point',(){
      final c=DrawingController(eventId:'e',actorId:'a');
      c.selectTool(FeatureKind.circle);
      expect(c.tapAt(const LatLng(48.7,2.0)),isNull);
      final f=c.tapAt(destination(const LatLng(48.7,2.0),300,45))!;
      expect(f.radiusM,closeTo(300,0.5));
    });

    test('a drag is a single undo step, and redo restores it',(){
      final c=DrawingController(eventId:'e',actorId:'a');
      c.selectTool(FeatureKind.point);
      final p=c.tapAt(const LatLng(48.7,2.0))!;
      c.beginEdit();
      for(var i=0;i<10;i++){c.moveSelected(0.001,0);}
      c.endEdit();
      expect(c.selected!.points.first.latitude,closeTo(48.71,1e-9));
      c.undo();
      expect(c.features.single.points.first,p.points.first);
      c.redo();
      expect(c.features.single.points.first.latitude,closeTo(48.71,1e-9));
    });

    test('delete, duplicate and style changes notify the store',(){
      final deleted=<String>[];
      final c=DrawingController(eventId:'e',actorId:'a',onDeleted:(f)=>deleted.add(f.id));
      c.selectTool(FeatureKind.text);
      final t=c.tapAt(const LatLng(48.7,2.0),label:'PC avancé')!;
      final copy=c.duplicateSelected()!;
      expect(c.features.length,2);
      expect(copy.label,'PC avancé');
      c.setColor(drawingPalette[3]);
      expect(c.selected!.color,drawingPalette[3]);
      c.deleteSelected();
      expect(deleted,[copy.id]);
      expect(c.features.single.id,t.id);
      c.undo();
      expect(c.features.length,2);
    });

    test('the map is locked only while editing or drawing freehand',(){
      final c=DrawingController(eventId:'e',actorId:'a');
      expect(c.locksMapDrag,isFalse);
      c.selectTool(FeatureKind.freehand);
      expect(c.locksMapDrag,isTrue);
      c.selectTool(FeatureKind.line);
      expect(c.locksMapDrag,isFalse);
      c.tapAt(const LatLng(48.7,2.0));c.tapAt(const LatLng(48.8,2.0));
      c.finish();
      expect(c.locksMapDrag,isTrue);
      c.select(null);
      expect(c.locksMapDrag,isFalse);
    });
  });

  group('synchronisation (ADR-001)',(){
    MapFeature remote(String id,{required DateTime at,String by='PCO',String label='',double lat=48.7})=>MapFeature(id:id,eventId:'e',kind:FeatureKind.point,points:[LatLng(lat,2.0)],color:0,strokeWidth:4,label:label,createdBy:by,updatedBy:by,updatedAt:at);

    test('new objects get time-ordered UUID v7 identifiers',(){
      final c=DrawingController(eventId:'e',actorId:'a');
      c.selectTool(FeatureKind.point);
      final f=c.tapAt(const LatLng(48.7,2.0))!;
      expect(f.id[14],'7');
      expect(f.updatedBy,'a');
    });

    test('a stale server state does not roll back a newer local edit',(){
      final c=DrawingController(eventId:'e',actorId:'a');
      final now=DateTime.now().toUtc();
      c.applyRemote(remote('x',at:now,label:'récent'));
      c.applyRemote(remote('x',at:now.subtract(const Duration(minutes:1)),label:'ancien'));
      expect(c.feature('x')!.label,'récent');
      c.applyRemote(remote('x',at:now.add(const Duration(seconds:1)),label:'plus récent'));
      expect(c.feature('x')!.label,'plus récent');
    });

    test('a remote delete older than the local copy is ignored',(){
      final c=DrawingController(eventId:'e',actorId:'a');
      final now=DateTime.now().toUtc();
      c.applyRemote(remote('x',at:now));
      c.removeRemote('x',at:now.subtract(const Duration(seconds:5)),by:'PCO');
      expect(c.feature('x'),isNotNull);
      c.removeRemote('x',at:now.add(const Duration(seconds:5)),by:'PCO');
      expect(c.feature('x'),isNull);
    });

    test('undo only touches its own objects, never remote changes',(){
      final changed=<String>[], deleted=<String>[];
      final c=DrawingController(eventId:'e',actorId:'TERRAIN-01',
        onChanged:(f,{required isNew})=>changed.add(f.id),onDeleted:(f)=>deleted.add(f.id));
      c.applyRemote(remote('pco-zone',at:DateTime.now().toUtc(),label:'du PCO'));
      c.selectTool(FeatureKind.point);
      final mine=c.tapAt(const LatLng(48.71,2.0))!;
      // The PCO edits its own object after my action.
      c.applyRemote(remote('pco-zone',at:DateTime.now().toUtc().add(const Duration(seconds:1)),label:'modifié au PCO'));
      changed.clear();
      c.undo();
      expect(c.feature(mine.id),isNull);
      expect(deleted,[mine.id]);
      expect(c.feature('pco-zone')!.label,'modifié au PCO');
      expect(changed,isEmpty);
    });

    test('undo of a delete restores the object with a fresh timestamp',(){
      final restored=<MapFeature>[];
      final c=DrawingController(eventId:'e',actorId:'a',onChanged:(f,{required isNew}){restored.add(f);});
      c.selectTool(FeatureKind.point);
      final f=c.tapAt(const LatLng(48.7,2.0))!;
      c.deleteSelected();
      restored.clear();
      c.undo();
      expect(restored.single.id,f.id);
      expect(restored.single.updatedAt.isAfter(f.updatedAt)||restored.single.updatedAt==f.updatedAt,isTrue);
    });

    test('a drag reports one change, at the end',(){
      var updates=0;
      final c=DrawingController(eventId:'e',actorId:'a',onChanged:(f,{required isNew}){if(!isNew)updates++;});
      c.selectTool(FeatureKind.point);
      c.tapAt(const LatLng(48.7,2.0));
      c.beginEdit();
      for(var i=0;i<20;i++){c.moveSelected(0.0001,0);}
      expect(updates,0);
      c.endEdit();
      expect(updates,1);
    });
  });
}
