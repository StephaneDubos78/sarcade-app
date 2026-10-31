import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/drawing/multi_select.dart';

// Card C1 of the cinématique review (31 Oct 2026): in « Sélectionner une
// zone », a drag moves the map; the rectangle needs a long press first.
Widget _host(SelectionRectOverlay o)=>MaterialApp(home:Scaffold(body:SizedBox(width:400,height:400,child:o)));

void main() {
  testWidgets('selection mode: a plain drag moves the map, no rectangle', (t) async {
    var moved=0; Rect? rect;
    await t.pumpWidget(_host(SelectionRectOverlay(onRect:(r)=>rect=r,onTap:(_){},onMoveStart:(_){},onMove:(_)=>moved++)));
    await t.dragFrom(const Offset(100,100),const Offset(120,80));
    await t.pumpAndSettle();
    expect(moved,greaterThan(0));
    expect(rect,isNull);
  });

  testWidgets('selection mode: long press then drag draws the rectangle', (t) async {
    Rect? rect;
    await t.pumpWidget(_host(SelectionRectOverlay(onRect:(r)=>rect=r,onTap:(_){},onMoveStart:(_){},onMove:(_){})));
    final g=await t.startGesture(const Offset(100,100));
    await t.pump(const Duration(milliseconds:700));
    await g.moveTo(const Offset(200,180)); await t.pump();
    await g.up(); await t.pumpAndSettle();
    expect(rect,isNotNull);
    expect(rect!.width,closeTo(100,1));
  });

  testWidgets('Maj held (no onMove): every drag draws the rectangle', (t) async {
    Rect? rect;
    await t.pumpWidget(_host(SelectionRectOverlay(onRect:(r)=>rect=r,onTap:(_){})));
    await t.dragFrom(const Offset(100,100),const Offset(80,60));
    await t.pumpAndSettle();
    expect(rect,isNotNull);
  });
}
