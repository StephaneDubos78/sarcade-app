// End-to-end test, step 2 (vault note « Tests automatiques de bout en bout »):
// the real Android app, in an emulator, is the field terminal ADR78-01; a
// real SARCADE server runs on the CI machine (10.0.2.2 from the emulator);
// the PCO is simulated through the server API from this test.
//
// Run by the CI job e2e-android:
//   flutter test integration_test/field_terminal_test.dart \
//     --dart-define=SARCADE_E2E_URL=http://10.0.2.2:8000 \
//     --dart-define=SARCADE_E2E_EVENT_NAME="E2E android 123"
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:sarcade_app/main.dart' as app;
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/ui/test_ids.dart';

const server = String.fromEnvironment('SARCADE_E2E_URL', defaultValue: 'http://10.0.2.2:8000');
const eventName = String.fromEnvironment('SARCADE_E2E_EVENT_NAME', defaultValue: 'E2E android');
const device = 'ADR78-01';

String _id() => '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';
String _iso() => DateTime.now().toUtc().toIso8601String();

/// The PCO, simulated through the API.
class Pco {
  final String eventId;
  Pco(this.eventId);

  Future<void> sync(String type, Map<String, dynamic> payload) async {
    final r = await http.post(Uri.parse('$server/api/v0.1/sync'), headers: {'Content-Type': 'application/json'},
        body: jsonEncode([{'operation_id': _id(), 'event_id': eventId, 'object_id': payload['id'], 'object_type': type,
          'action': 'create', 'client_time': _iso(), 'payload': payload}]));
    expect(r.statusCode, 200, reason: 'sync answered');
    expect((jsonDecode(r.body) as List).first['status'], 'accepted', reason: '$type accepted');
  }

  Future<Map<String, dynamic>> send(String body, {List<String> to = const [], String priority = 'urgent'}) async {
    final m = {'id': _id(), 'event_id': eventId, 'sender_id': 'PCO', 'recipient_ids': to, 'priority': priority,
      'body': body, 'created_at': _iso()};
    await sync('message', m);
    return m;
  }

  Future<List<Map<String, dynamic>>> changes() async {
    final r = await http.get(Uri.parse('$server/api/v0.1/events/$eventId/sync/changes?after=0&limit=2000'));
    return ((jsonDecode(r.body) as Map)['changes'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<String>> devices() async {
    final r = await http.get(Uri.parse('$server/api/v0.1/events/$eventId/devices'));
    return (jsonDecode(r.body) as List).map((d) => '${d['device_id']}').toList();
  }
}

Future<String> eventIdByName(String name) async {
  final r = await http.get(Uri.parse('$server/api/v0.1/events'));
  final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  return list.firstWhere((e) => e['name'] == name)['id'] as String;
}

/// The map page never settles (timers, realtime): pump until [finder] shows.
Future<void> pumpUntil(WidgetTester t, Finder finder, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('not shown within ${timeout.inSeconds}s: $finder\nOn screen: ${screenTexts()}');
}

/// Texts currently on screen, for the failure message (the CI screenshots
/// are not always reachable).
String screenTexts() => find.byType(Text).evaluate()
    .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '')
    .where((s) => s.trim().isNotEmpty).take(60).join(' | ');

/// Waits for a server-side condition while the app keeps running.
Future<void> pumpUntilTrue(WidgetTester t, Future<bool> Function() check, Object what,
    {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 500));
    if (await check()) return;
  }
  fail('not true within ${timeout.inSeconds}s: ${what is String Function() ? what() : what}\nOn screen: ${screenTexts()}');
}

Finder field(String labelKey) => find.ancestor(of: find.text(S.t(labelKey)), matching: find.byType(TextField)).first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('field terminal on Android: join, receive and acknowledge, send', (t) async {
    final eventId = await eventIdByName(eventName);
    final pco = Pco(eventId);
    final run = DateTime.now().millisecondsSinceEpoch.toString().substring(7);

    // 1. First run: server, event chosen in the list, identifier.
    app.main();
    // S.t follows the language chosen by the app at start (device language).
    await t.pump(const Duration(seconds: 2));
    await pumpUntil(t, find.text(S.t('settings.server')));
    await t.enterText(field('settings.server'), server);
    await t.pump();
    // Leaving the field loads the events of that server.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump(const Duration(seconds: 1));
    // The list loads when the server is entered (a spinner replaces the
    // refresh button meanwhile); reload until the test event is offered.
    var listed = false;
    for (var attempt = 0; attempt < 5 && !listed; attempt++) {
      await pumpUntil(t, find.byTooltip(S.t('settings.eventsRefresh')));
      // The event list (the remembered servers list sits above it).
      await t.tap(find.ancestor(of: find.text(S.t('settings.event')), matching: find.byType(DropdownButtonFormField<String>)).first);
      await t.pump(const Duration(seconds: 1));
      listed = find.textContaining(eventName).evaluate().isNotEmpty;
      if (!listed) {
        await t.tapAt(const Offset(5, 5)); // closes the menu
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(find.byTooltip(S.t('settings.eventsRefresh')));
        await t.pump(const Duration(seconds: 2));
      }
    }
    expect(listed, isTrue, reason: 'event « $eventName » offered in the list\nOn screen: ${screenTexts()}');
    await t.tap(find.textContaining(eventName).last);
    await t.pump(const Duration(seconds: 1));
    // Fields below the fold are built only once scrolled to.
    await t.scrollUntilVisible(find.text(S.t('settings.device')), 200, scrollable: find.byType(Scrollable).first);
    // Retyped until the field really holds it (a first entry was sometimes
    // lost while the list reload rebuilt the form, leaving « device-demo »).
    for (var attempt = 0; attempt < 5; attempt++) {
      await t.enterText(field('settings.device'), device);
      await t.pump(const Duration(milliseconds: 500));
      final value = t.widget<TextField>(field('settings.device')).controller?.text;
      if (value == device) break;
    }
    expect(t.widget<TextField>(field('settings.device')).controller?.text, device, reason: 'terminal identifier entered');
    final save = find.text(S.t('common.save'));
    await t.scrollUntilVisible(save, 200, scrollable: find.byType(Scrollable).first);
    FocusManager.instance.primaryFocus?.unfocus(); // keyboard down
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(save);
    await pumpUntil(t, find.byTooltip(S.t('map.messages')));
    var seen = <String>[];
    await pumpUntilTrue(t, () async => (seen = await pco.devices()).contains(device),
        () => 'the server knows $device (devices: $seen)', timeout: const Duration(seconds: 90));

    // 2. PCO → field: urgent broadcast, received and acknowledged by the app.
    final urgent = await pco.send('E2E urgent from PCO $run');
    await pumpUntilTrue(t, () async => (await pco.changes()).any((c) => c['object_type'] == 'ack'
        && c['payload']['message_id'] == urgent['id'] && c['payload']['actor_id'] == device
        && c['payload']['status'] == 'received'), 'ACK « received » from $device');
    // Leave the urgent notification on screen a few seconds: opening the
    // messages marks it read and removes it (notification actions, lot 3),
    // before the Android watcher of e2e/android/run.sh could read it.
    // Unstable test (« urgent message notification not shown »): the
    // pumps of a live test do not wait real time, so the messages could
    // open before the watcher's next sample. Wait until Android really
    // shows the notification, then 4 real seconds (watcher every 1 s).
    final notifications = FlutterLocalNotificationsPlugin();
    await pumpUntilTrue(t, () async {
      final active = await notifications.getActiveNotifications();
      return active.any((n) => '${n.title} ${n.body}'.contains('E2E urgent from PCO $run'));
    }, 'urgent notification shown by Android', timeout: const Duration(seconds: 30));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    await t.pump();
    await t.tap(find.byTooltip(S.t('map.messages')));
    // Phone (29 Oct 2026, like WhatsApp): the list of the conversations
    // first, its last message in the line; a touch opens the conversation.
    await pumpUntil(t, find.textContaining('E2E urgent from PCO $run'));
    await t.tap(find.textContaining('E2E urgent from PCO $run').first);
    await pumpUntil(t, find.text('E2E urgent from PCO $run'));

    // 3. Field → PCO: message written in the app reaches the server.
    final body = 'E2E from $device $run';
    await t.enterText(find.ancestor(of: find.text(S.t('messages.hint')), matching: find.byType(TextField)).first, body);
    await t.pump();
    await t.tap(find.byTooltip(S.t('messages.send')));
    await pumpUntilTrue(t, () async => (await pco.changes()).any((c) => c['object_type'] == 'message'
        && c['payload']['body'] == body && c['payload']['sender_id'] == device), 'message from $device on the server');

    // 4. Message brought by the synchronisation (realtime missed): the app
    //    still acknowledges it (fix of the lot 2 recette, 25 October 2026).
    //    Sent while the app is on the messages page; the periodic sync or the
    //    realtime channel brings it: either way an ACK must come back.
    final routine = await pco.send('E2E routine from PCO $run', priority: 'routine');
    await pumpUntilTrue(t, () async => (await pco.changes()).any((c) => c['object_type'] == 'ack'
        && c['payload']['message_id'] == routine['id'] && c['payload']['actor_id'] == device),
        'ACK of the routine message', timeout: const Duration(seconds: 90));

    // 5. Cinématique on Android (vault, revue du 31 Oct 2026, point E):
    //    the system back gesture leaves each screen, then the map.
    Finder byId(String id) => find.byWidgetPredicate((w) => hasTestId(w, id));
    // The system back of Android, without its last step: on the map with
    // nothing open, the real gesture closes the app (the test would hang);
    // maybePop runs the same PopScope of the map page but never quits.
    Future<void> back() async {
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pump(const Duration(seconds: 1));
    }
    Future<void> onMap(String what) async {
      await pumpUntil(t, byId('map.map-layers'), timeout: const Duration(seconds: 10));
      expect(byId('map.map-layers').hitTestable(), findsOneWidget, reason: '$what: the map is back\nOn screen: ${screenTexts()}');
    }
    // Conversation, then the list of the conversations, then the map.
    await back(); await back();
    await onMap('messages › back');
    // Itinéraires and Résection (blocked on a phone before lot 12).
    for (final tool in ['tool.routes', 'tool.resection']) {
      await t.tap(byId('nav.tools')); await pumpUntil(t, byId(tool));
      await t.tap(byId(tool)); await t.pump(const Duration(seconds: 1));
      await back();
      await onMap('$tool › back');
    }
    // « Sélectionner une zone » (card C1): back leaves the selection first.
    final centre = t.getCenter(find.byType(Scaffold).first);
    await t.longPressAt(centre - const Offset(120, 200)); await t.pump(const Duration(seconds: 1));
    await pumpUntil(t, byId('point.select'));
    await t.tap(byId('point.select')); await t.pump(const Duration(seconds: 1));
    expect(find.text(S.t('draw.selectHint')), findsOneWidget, reason: 'selection mode on');
    await back();
    expect(find.text(S.t('draw.selectHint')), findsNothing, reason: 'back leaves the selection\nOn screen: ${screenTexts()}');
    await onMap('selection › back');
  });
}
