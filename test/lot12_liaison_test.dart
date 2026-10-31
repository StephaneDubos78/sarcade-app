import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/stations.dart' show ServerLink;
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/ui/link_status.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('dot alone when connected, word and pending items otherwise', () {
    expect(linkText(ServerLink.direct, 0), '');
    expect(linkText(ServerLink.direct, 2), '2');
    expect(linkText(ServerLink.cut, 3), 'Coupée · 3');
    expect(linkText(ServerLink.slowed, 0), 'Ralentie');
    const scheme = ColorScheme.light();
    expect(linkColor(ServerLink.direct, scheme), const Color(0xFF2E9D4B));
    expect(linkColor(ServerLink.cut, scheme), scheme.error);
  });

  testWidgets('every app bar ends with the link pill (hidden without an event)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(appBar: LinkedAppBar(title: Text('Météo')))));
    expect(find.byType(LinkStatusPill), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(appBar: LinkedAppBar(title: Text('Paramètres'), linkStatus: false))));
    expect(find.byType(LinkStatusPill), findsNothing);
  });
}
