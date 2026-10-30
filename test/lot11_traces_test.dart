import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/traces_layer.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('APRS traces on by default, 2 h by default, a choice kept', () {
    expect(aprsTracesFrom(null), isTrue);
    expect(aprsTracesFrom('0'), isFalse);
    expect(aprsTracesFrom('1'), isTrue);
    expect(defaultTraceWindow, 120);
    expect(traceWindowFrom(null), 120);
  });

  testWidgets('« Durée des traces » titles the choices', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: traceWindowChips(120, (_) {}))));
    expect(find.text('Durée des traces'), findsOneWidget);
    expect(find.byKey(const ValueKey('trace-window-120')), findsOneWidget);
  });
}
