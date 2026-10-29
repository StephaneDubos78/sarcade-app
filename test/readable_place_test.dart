import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:sarcade_app/src/features/places/readable_place.dart';
import 'package:sarcade_app/src/l10n/strings.dart';
import 'package:sarcade_app/src/services/sarcade_api.dart';

const answer = {'label': '800 m au nord de Plaisir', 'label_en': '800 m north of Plaisir',
  'road': {'name': 'Rue de la Gare'}};

void main() {
  tearDown(() => S.setLanguage('fr'));

  test('text in the language of the application, road after the commune', () {
    S.setLanguage('fr');
    expect(placeText(answer), '800 m au nord de Plaisir · Rue de la Gare');
    expect(placeText(answer, withRoad: false), '800 m au nord de Plaisir');
    S.setLanguage('en');
    expect(placeText(answer), '800 m north of Plaisir · Rue de la Gare');
    expect(placeText({'label': null, 'road': null}), isNull);
    expect(placeText(null), isNull);
  });

  test('distress suffix, cached, empty when the server fails', () async {
    var calls = 0;
    final ok = PlaceDescriber(SarcadeApi(baseUrl: 'http://s', client: MockClient((r) async {
      calls++;
      expect(r.url.path, '/api/v0.1/places/describe');
      return http.Response(jsonEncode(answer), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    })));
    expect(await ok.distressSuffix(const LatLng(48.82, 1.95)), ' (800 m au nord de Plaisir)');
    await ok.distressSuffix(const LatLng(48.82001, 1.95001));
    expect(calls, 1);
    expect(await ok.distressSuffix(null), '');
    final down = PlaceDescriber(SarcadeApi(baseUrl: 'http://s', client: MockClient((r) async => http.Response('', 404))));
    expect(await down.distressSuffix(const LatLng(48.82, 1.95)), '');
    final slow = PlaceDescriber(SarcadeApi(baseUrl: 'http://s', client: MockClient((r) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      return http.Response(jsonEncode(answer), 200);
    })));
    expect(await slow.distressSuffix(const LatLng(48.82, 1.95), timeout: const Duration(milliseconds: 50)), '');
  });
}
