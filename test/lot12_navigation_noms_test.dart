import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/navigation/navigation_widgets.dart' show navNoticeColor;
import 'package:sarcade_app/src/features/navigation/point_label.dart';
import 'package:sarcade_app/src/features/settings/diagnostics_panel.dart' show routingWhere;
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  tearDown(() => S.setLanguage('fr'));

  test('default names in the language of each device', () {
    S.setLanguage('fr');
    expect(pointLabel('Map point'), 'Point de la carte');
    expect(pointLabel(''), 'Point de la carte');
    expect(pointLabel(null), 'Point de la carte');
    expect(pointLabel('Gué de la Mauldre'), 'Gué de la Mauldre');
    S.setLanguage('en');
    expect(pointLabel('Point de la carte'), 'Map point');
  });

  test('straight line for lack of engine: information in orange; Diagnostic', () {
    expect(navNoticeColor('engine_unavailable', Colors.red), const Color(0xFFE8710A));
    expect(navNoticeColor('no_route', Colors.red), Colors.red);
    expect(navNoticeColor('on_device', Colors.red), isNull);
    expect(routingWhere(server: true, device: false), 'server');
    expect(routingWhere(server: false, device: true), 'device');
    expect(routingWhere(server: false, device: false), 'none');
    S.setLanguage('fr');
    expect(S.t('nav.notice.engine_unavailable'), startsWith('Itinéraire en ligne droite'));
  });
}
