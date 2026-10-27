import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/config/saved_servers.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 26, 1);
  test('the public server is always offered', () {
    final list = parseSavedServers(null);
    expect(list.single.url, defaultServerUrl);
    expect(canRemoveServer(list.single), isFalse);
    expect(parseSavedServers('not json').length, 1);
  });
  test('remembered at the first connection, with event and terminal', () {
    var list = rememberServer(parseSavedServers(null), 'http://192.168.0.110:8000/', eventId: 'e1', deviceId: 'PCO', now: t0);
    expect(list.length, 2);
    final nas = findServer(list, 'HTTP://192.168.0.110:8000')!;
    expect(nas.label, '192.168.0.110:8000');
    expect(nas.lastEvent, 'e1');
    list = rememberServer(list, 'http://192.168.0.110:8000', now: t0.add(const Duration(hours: 1)));
    expect(list.length, 2);
    expect(findServer(list, 'http://192.168.0.110:8000')!.lastEvent, 'e1', reason: 'kept when not given');
    final round = parseSavedServers(encodeSavedServers(list));
    expect(round.map((s) => s.url), list.map((s) => s.url));
    expect(findServer(round, 'http://192.168.0.110:8000')!.lastDevice, 'PCO');
  });
  test('at most 10: the oldest goes, never the public one', () {
    var list = parseSavedServers(null);
    for (var i = 0; i < 12; i++) {
      list = rememberServer(list, 'http://10.0.0.$i:8000', now: t0.add(Duration(minutes: i)));
    }
    expect(list.length, maxSavedServers);
    expect(findServer(list, defaultServerUrl), isNotNull);
    expect(findServer(list, 'http://10.0.0.0:8000'), isNull);
    expect(findServer(list, 'http://10.0.0.11:8000'), isNotNull);
  });
}
