import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/map/operational_map_page.dart' show operatorsTitle;
import 'package:sarcade_app/src/features/messages/conversations.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  setUp(() => S.setLanguage('fr'));

  test('revue n° 8, 36, 44: numbered terminals by their 2 last characters', () {
    expect(avatarInitials('TEL-01'), '01');
    expect(avatarInitials('TEL-04'), '04');
    expect(avatarInitials('PCO-Web'), 'PW');
    expect(avatarInitials('F4JPO-9'), 'JPO');
  });

  test('revue n° 42, 57, 6, 17, 20, 29, 40, 49: texts', () {
    expect(operatorsTitle(4, 2), 'Opérateurs (4) · Stations (2)');
    expect(operatorsTitle(4, 0), 'Opérateurs (4)');
    expect(S.t('aprs.packets', {'n': 1}), '1 paquet');
    expect(S.t('aprs.packets', {'n': 2}), '2 paquets');
    expect(S.t('search.hint'), 'Rechercher');
    expect(S.t('bearings.strength'), 'Force du signal (S1 à S9)');
    expect(S.t('point.order'), 'Envoyer une équipe');
    expect(S.t('bearings.colorBy'), 'Couleur des relevés');
    expect(S.t('groups.members'), 'Membres');
    expect(S.t('files.importDrawings'), 'Importer des dessins');
  });
}
