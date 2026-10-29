import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/settings/about_page.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/ui/theme.dart';

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
    // General tab: server, event (no remote event loader), terminal.
    await tester.enterText(find.byType(TextFormField).at(1), 'unsaved-event');
    await tester.tap(find.text('Diagnostic'));
    await tester.pumpAndSettle();
    expect(find.text('Événement actif : active-event'), findsOneWidget);
    expect(find.text('unsaved-event'), findsNothing);
    await tester.tap(find.text('Ouvrir'));
    expect(logbookOpened, isTrue);
    expect(saves, 0);
    await tester.ensureVisible(find.text('Général'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Général'));
    await tester.pumpAndSettle();
    expect(find.text('unsaved-event'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('first setup offers About but no operational diagnostics', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config, firstRun: true, onSave: (_) async {},
      onOpenLogbook: () {},
    )));
    expect(find.text('Diagnostic'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    await tester.tap(find.text('À propos'));
    await tester.pumpAndSettle();
    expect(find.text('Édité par SDUBOS Consulting'), findsOneWidget);
  });

  testWidgets('theme: day, night or automatic, applied at once and kept', (tester) async {
    ThemeMode? kept;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config, onSave: (_) async {}, onThemeChanged: (m) => kept = m,
    )));
    await tester.tap(find.text('Affichage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuit'));
    await tester.pumpAndSettle();
    expect(themeMode.value, ThemeMode.dark);
    expect(kept, ThemeMode.dark);
    await tester.tap(find.text('Automatique'));
    await tester.pumpAndSettle();
    expect(themeMode.value, ThemeMode.system);
    expect(kept, ThemeMode.system);
  });

  test('automatic theme by default', () {
    expect(themeModeFrom(null), ThemeMode.system);
    expect(themeModeFrom('dark'), ThemeMode.dark);
    expect(themeModeFrom('light'), ThemeMode.light);
  });

  testWidgets('a refused field in a hidden tab is shown', (tester) async {
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: SettingsPage(
      initial: config, onSave: (_) async { saves++; },
    )));
    await tester.enterText(find.byType(TextFormField).at(2), '');
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Champ obligatoire'), findsOneWidget);
    expect(saves, 0);
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
    await tester.scrollUntilVisible(find.text('Credits and component licences'), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}
