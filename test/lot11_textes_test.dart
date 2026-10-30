import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/weather/weather_models.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/models/message.dart';
import 'package:sarcade_app/src/services/event_names.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('revue n° 35: priorities translated, never the technical name', () {
    expect(S.t(priorityKey('distress')), 'Détresse');
    expect(S.t(priorityKey('normal')), 'Routine');
    expect(S.t(priorityKey('whatever')), 'Routine');
    expect(S.t(priorityKey('immediate')), 'Immédiat');
    expect(priorityRed('distress'), isTrue);
    expect(priorityRed('urgent'), isFalse);
    expect(priorityRaised('distress'), isTrue);
    expect(priorityRaised('normal'), isFalse);
  });

  test('revue n° 50: no « Prévision du - » without a forecast', () {
    expect(weatherShowsStale(const WeatherReport(), offline: true), isFalse);
    expect(weatherShowsStale(null, offline: true), isFalse);
    final r = WeatherReport(fetchedAt: DateTime(2026, 10, 30, 8), hours: [WeatherHour.fromJson({'time': '2026-10-30T09:00:00Z', 'temperature_c': 12})]);
    expect(weatherShowsStale(r, offline: false), isTrue);
  });

  test('revue n° 60: name of the event, identifier in the report only', () {
    final events = [{'id': 'a79364b2', 'name': 'Exercice ADRASEC 78 Versailles'}, {'id': 'b', 'name': ' '}];
    expect(eventNameIn(events, 'a79364b2'), 'Exercice ADRASEC 78 Versailles');
    expect(eventNameIn(events, 'b'), isNull);
    expect(eventNameIn(events, 'zz'), isNull);
    expect(eventReportValue('Exercice', 'a79364b2'), 'Exercice (a79364b2)');
    expect(eventReportValue(null, 'a79364b2'), 'a79364b2');
    expect(S.t('event.intro', {'event': 'Exercice'}), startsWith('Réglages de Exercice'));
  });

  test('revue n° 69: vouvoiement', () {
    for (final k in ['settings.intro', 'measure.noPosition', 'measure.pickOrigin', 'access.required', 'access.desktopIntro', 'access.pasteIntro',
        'update.requiredDetail', 'update.store', 'weather.bulletinCopied', 'settings.dndPending', 'ext.warning', 'settings.callsignHelp']) {
      expect(RegExp(r'\b(ton|ta|tes|toi|te)\b|choisis |indique |touche |connecte-toi|colle-le|copie-le').hasMatch(S.t(k)), isFalse, reason: k);
    }
  });
}
