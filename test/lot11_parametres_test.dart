import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  tearDown(() => S.setLanguage('fr'));

  test('agreements instead of « (s) »', () {
    S.setLanguage('fr');
    expect(S.t('event.aprsFollowedHelp', {'g': 2, 'c': 0}), '2 groupes, aucun indicatif ajouté');
    expect(S.t('event.aprsFollowedHelp', {'g': 1, 'c': 1}), '1 groupe, 1 indicatif ajouté');
    expect(S.t('event.quickHelp', {'n': 0}), startsWith('aucun message propre à l’événement'));
    expect(S.t('event.quickHelp', {'n': 3}), startsWith('3 messages propres'));
    expect(S.t('files.folderCount', {'n': 1}), '1 fichier');
    expect(S.t('sync.alert', {'n': 3, 'min': 7}), '3 éléments non envoyés depuis 7 min');
    expect(S.t('sync.alert', {'n': 1, 'min': 7}), '1 élément non envoyé depuis 7 min');
    expect(S.t('draw.points', {'n': 0}), '0 point');
    S.setLanguage('en');
    expect(S.t('draw.points', {'n': 0}), '0 points');
    expect(S.t('draw.points', {'n': 1}), '1 point');
    expect(S.t('event.aprsFollowedHelp', {'g': 0, 'c': 2}), 'no groups, 2 added callsigns');
  });
}
