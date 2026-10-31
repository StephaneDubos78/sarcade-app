import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tools/tools_page.dart';
import 'package:sarcade_app/src/ui/test_ids.dart';

// Card B of the cinématique review (31 Oct 2026): stable identifiers.
Finder byId(String id) => find.byWidgetPredicate((w) => hasTestId(w, id));

void main() {
  testWidgets('withId gives a semantics node with the identifier', (t) async {
    await t.pumpWidget(MaterialApp(home: withId('nav.tools', TextButton(onPressed: () {}, child: const Text('Outils')))));
    expect(byId('nav.tools'), findsOneWidget);
  });

  testWidgets('each tool has its identifier', (t) async {
    await t.pumpWidget(MaterialApp(home: ToolsPage(items: [
      ToolItem(id: 'weather', icon: Icons.cloud_outlined, title: 'Météo', subtitle: '', color: Colors.orange, onTap: () {}),
      ToolItem(id: 'routes', icon: Icons.route, title: 'Itinéraires', subtitle: '', color: Colors.green, onTap: () {}),
    ])));
    expect(byId('tool.weather'), findsOneWidget);
    expect(byId('tool.routes'), findsOneWidget);
  });
}
