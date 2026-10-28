import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/settings/about_page.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

const config = AppConfig(
  serverUrl: 'https://example.org', eventId: 'active-event', deviceId: 'TEST',
  tileUrl: '', tileAttribution: '', language: 'fr',
);

void main() {
  setUp(() => S.setLanguage('fr'));
  tearDown(() => S.setLanguage('fr'));

  testWidgets('diagnostics uses the active event without saving or losing edits', (tester) async {
    var saves = 0;
    var logbookOpened = false;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config,
      onSave: (_) async { saves++; },
      onOpenLogbook: () { logbookOpened = true; },
    )));
    // The second field is the event when no remote event loader is supplied.
    await tester.enterText(find.byType(TextFormField).at(1), 'unsaved-event');
    await tester.scrollUntilVisible(find.text('Diagnostic'), 300);
    await tester.tap(find.text('Diagnostic'));
    await tester.pumpAndSettle();
    expect(find.text('Événement actif : active-event'), findsOneWidget);
    expect(find.textContaining('unsaved-event'), findsNothing);
    await tester.tap(find.text('Main courante'));
    expect(logbookOpened, isTrue);
    expect(saves, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('unsaved-event'), -300);
    expect(find.text('unsaved-event'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('first setup offers About but no operational diagnostics', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config, firstRun: true, onSave: (_) async {},
      onOpenLogbook: () {},
    )));
    await tester.scrollUntilVisible(find.text('À propos de SARCADE'), 300);
    expect(find.text('Diagnostic'), findsNothing);
    await tester.tap(find.text('À propos de SARCADE'));
    await tester.pumpAndSettle();
    expect(find.byType(SarcadeAboutPage), findsOneWidget);
    expect(find.text('Édité par SDUBOS Consulting'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('About is translated and readable on a narrow screen with large text', (tester) async {
    S.setLanguage('en');
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const SarcadeAboutPage(),
    ));
    expect(find.text('About SARCADE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Credits and component licences'), 300);
    expect(tester.takeException(), isNull);
  });
}
