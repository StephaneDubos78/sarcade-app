import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_toolbar.dart';
import 'package:sarcade_app/src/features/map/layer_row.dart';
import 'package:sarcade_app/src/features/routes/route_entry_bar.dart';
import 'package:sarcade_app/src/features/search/map_search_bar.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  test('revue n° 21, 28, 52: phone layouts below 600 px', () {
    expect(drawingToolbarWraps(390), isTrue);
    expect(drawingToolbarWraps(820), isFalse);
    expect(layerRowStacksAction(390), isTrue);
    expect(layerRowStacksAction(1440), isFalse);
    expect(sidePanelFullScreen(390), isTrue);
    expect(sidePanelFullScreen(820), isFalse);
  });

  test('revue n° 53: a magnifier when the search has no room', () {
    expect(searchAsIcon(90, typing: false), isTrue);
    expect(searchAsIcon(90, typing: true), isFalse);
    expect(searchAsIcon(300, typing: false), isFalse);
  });

  test('itinéraires: « Itinéraires », never « Routes »', () {
    S.setLanguage('fr');
    expect(S.t('routes.title'), 'Itinéraires');
    expect(S.t('routes.undoPoint'), 'Annuler le dernier point');
    expect(S.t('routes.entrySummary', {'d': '1,2 km', 'n': 3}), '1,2 km · 3 points');
  });

  testWidgets('revue n° 28: « Voir la liste » under the name on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
      LayerRow(label: 'Points d’intérêt (1)', on: true, onShown: (_) {}, opacity: 1, onOpacity: (_) {},
        trailing: TextButton(key: const ValueKey('see'), onPressed: () {}, child: const Text('Voir la liste'))),
    ]))));
    final label = tester.getTopLeft(find.text('Points d’intérêt (1)'));
    final see = tester.getTopLeft(find.byKey(const ValueKey('see')));
    expect(see.dy, greaterThan(label.dy + 20));
  });
}
