import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/platform/startup_report.dart';

// Card « Client Windows : écran gris au démarrage » (31 Oct 2026).
void main() {
  test('errors are kept for the smoke report', () {
    StartupReport.errors.clear();
    StartupReport.error('test', StateError('boom'), StackTrace.current);
    expect(StartupReport.errors.single, contains('boom'));
    expect(StartupReport.smokeJson(), contains('"errors"'));
    StartupReport.errors.clear();
  });

  testWidgets('a failing widget shows a readable message, not grey', (t) async {
    await t.pumpWidget(readableErrorWidget(FlutterErrorDetails(exception: StateError('boom'))));
    expect(find.textContaining('Display error'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('startup error screen: message and copy button', (t) async {
    await t.pumpWidget(const StartupErrorApp(message: 'Hive: access denied'));
    expect(find.text('SARCADE n’a pas pu démarrer'), findsOneWidget);
    expect(find.textContaining('Hive: access denied'), findsOneWidget);
    expect(find.text('Copier / Copy'), findsOneWidget);
  });
}
