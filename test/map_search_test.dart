import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/dictation/dictation.dart';
import 'package:sarcade_app/src/features/search/map_search.dart';

void main() {
  const items = [
    Searchable(SearchKind.reference, 'PH 12 Château d\'eau', 'point haut', LatLng(48.8, 1.9)),
    Searchable(SearchKind.operator, 'F4JPO-5', 'aprs', LatLng(48.82, 1.91)),
    Searchable(SearchKind.drawing, 'Zone de recherche', 'zone', LatLng(48.7, 2.0)),
  ];
  test('accents and word order ignored', () {
    expect(matchesQuery('chateau ph', 'PH 12 Château d\'eau'), isTrue);
    expect(matchesQuery('relais', 'PH 12 Château d\'eau'), isFalse);
  });
  test('local results by kind, coordinates first', () {
    expect(searchLocal('f4jpo', items).single.title, 'F4JPO-5');
    final r = searchLocal('48.82, 1.91', items);
    expect(r.first.kind, SearchKind.coordinates);
    expect(searchLocal('z', items), isEmpty);
  });
  test('addresses of the server', () {
    final r = addressResults({'results': [
      {'label': 'Rue des Côteaux de Chatron', 'postcode': '78640', 'city': 'Saint-Germain-de-la-Grange', 'lat': 48.823, 'lon': 1.909},
      {'label': 'bad'},
    ]});
    expect(r.single.subtitle, '78640 Saint-Germain-de-la-Grange');
  });
  test('dictation', () {
    expect(dictatedText('', 'bonjour PCO'), 'Bonjour PCO');
    expect(dictatedText('Message :', 'en route'), 'Message : en route');
    expect(dictatedText('abc ', ''), 'abc ');
    expect(dictationOffered(isWeb: false, targetPlatform: 'windows'), isFalse);
    expect(dictationOffered(isWeb: true, targetPlatform: 'windows'), isTrue);
    expect(dictationLocale('fr'), 'fr_FR');
  });
}
