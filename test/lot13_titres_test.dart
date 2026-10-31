import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/link_status.dart';

// Card C3 of the cinématique review (31 Oct 2026): on a phone the
// secondary actions give way to the title.
void main() {
  test('layout of the secondary actions by screen width', () {
    expect(appBarActionsLayout(1440, 2), 'wide');
    expect(appBarActionsLayout(820, 2), 'wide');
    expect(appBarActionsLayout(390, 1), 'icons');
    expect(appBarActionsLayout(390, 2), 'menu');
  });

  testWidgets('phone: two actions go in ⋮, the title gets the room', (t) async {
    t.view.physicalSize = const Size(390, 844); t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var hits = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(appBar: LinkedAppBar(linkStatus: false, title: const Text('Météo de l’événement'), secondary: [
      AppBarAction(icon: Icons.campaign_outlined, label: 'Diffuser', onPressed: () => hits++, written: true),
      AppBarAction(icon: Icons.refresh, label: 'Actualiser', onPressed: () {}),
    ]))));
    expect(find.byKey(const ValueKey('appbar-more')), findsOneWidget);
    expect(find.text('Diffuser'), findsNothing);
    await t.tap(find.byKey(const ValueKey('appbar-more'))); await t.pumpAndSettle();
    await t.tap(find.text('Diffuser')); await t.pumpAndSettle();
    expect(hits, 1);
  });

  testWidgets('computer: « Diffuser » written, no ⋮', (t) async {
    t.view.physicalSize = const Size(1440, 900); t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(appBar: LinkedAppBar(linkStatus: false, title: const Text('Météo'), secondary: [
      AppBarAction(icon: Icons.campaign_outlined, label: 'Diffuser', onPressed: () {}, written: true),
      AppBarAction(icon: Icons.refresh, label: 'Actualiser', onPressed: () {}),
    ]))));
    expect(find.byKey(const ValueKey('appbar-more')), findsNothing);
    expect(find.text('Diffuser'), findsOneWidget);
  });
}
