import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/settings/settings_page.dart' show settingsShowsSaveBar;
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  test('revue n° 64: no save bar on Diagnostic and À propos', () {
    expect(settingsShowsSaveBar(tab: 'diagnostics', firstRun: false, dirty: false), isFalse);
    expect(settingsShowsSaveBar(tab: 'about', firstRun: false, dirty: false), isFalse);
    expect(settingsShowsSaveBar(tab: 'general', firstRun: false, dirty: false), isTrue);
    expect(settingsShowsSaveBar(tab: 'about', firstRun: false, dirty: true), isTrue);
    expect(settingsShowsSaveBar(tab: 'about', firstRun: true, dirty: false), isTrue);
  });

  test('revue n° 51: « Diffuser »', () {
    S.setLanguage('fr');
    expect(S.t('weather.broadcast'), 'Diffuser');
  });
}
