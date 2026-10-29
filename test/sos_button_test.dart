import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/sos_button.dart';

/// SOS held 2 s (29 Oct 2026): the hold must reach the end even with the
/// mouse, and a short touch must not send anything.
void main() {
  Future<int> hold(WidgetTester t, Duration d) async {
    var sent = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: SosButton(inDistress: false, onTriggered: () => sent++, onEnd: () {})))));
    final g = await t.startGesture(t.getCenter(find.byType(SosButton)));
    await t.pump(d);
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    return sent;
  }

  testWidgets('held 2 s: the distress is sent', (t) async {
    expect(await hold(t, const Duration(milliseconds: 2100)), 1);
  });

  testWidgets('short touch: nothing sent, the hint is shown', (t) async {
    expect(await hold(t, const Duration(milliseconds: 600)), 0);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
