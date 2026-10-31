import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/measure/external_maps.dart';
import 'package:sarcade_app/src/l10n/strings.dart';

void main() {
  const p = LatLng(48.80145, 2.13047);

  test('Waze and Google Maps on their own lines', () {
    expect(openInChoices(android: true, ios: false), ['waze', 'google_maps', 'organic_maps', 'osmand', 'other']);
    expect(openInChoices(android: false, ios: true), ['waze', 'google_maps', 'organic_maps', 'osmand', 'apple_maps']);
    expect(openInChoices(android: false, ios: false), ['waze', 'google_maps', 'openstreetmap']);
    expect(openInChoices(android: true, ios: false, hideTracking: true), isNot(contains('waze')));
  });

  test('links of each application', () {
    expect(openInLink('waze', p, 'X', android: true, ios: false), contains('waze.com/ul?ll=48.801450,2.130470&navigate=yes'));
    expect(openInLink('google_maps', p, 'X', android: false, ios: false), contains('destination=48.801450,2.130470'));
    expect(openInLink('other', p, 'Gué', android: true, ios: false), startsWith('geo:48.801450,2.130470'));
    expect(openInLink('openstreetmap', p, 'X', android: false, ios: false), contains('mlat=48.801450'));
    expect(openInLink('osmand', p, 'X', android: false, ios: true), startsWith('osmandmaps://'));
  });

  test('texts', () {
    S.setLanguage('fr');
    expect(S.t('ext.always'), 'Toujours ouvrir avec cette application');
    expect(S.t('ext.app.other'), 'Autre application');
  });
}
