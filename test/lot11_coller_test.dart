import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tools/paste_locations.dart';

void main() {
  void near(FoundLocation f, double lat, double lon) {
    expect(f.point.latitude, closeTo(lat, 0.001));
    expect(f.point.longitude, closeTo(lon, 0.001));
  }

  test('links: Google Maps, Apple Plans, OpenStreetMap, Waze, geo:', () {
    near(findLocations('https://www.google.com/maps/place/X/@48.80145,2.13047,17z').single, 48.80145, 2.13047);
    near(findLocations('https://maps.apple.com/?ll=48.8014,2.1304&q=Point').single, 48.8014, 2.1304);
    near(findLocations('https://www.openstreetmap.org/?mlat=48.8014&mlon=2.1304#map=17/48.8014/2.1304').single, 48.8014, 2.1304);
    near(findLocations('https://waze.com/ul?ll=48.8014%2C2.1304&navigate=yes').single, 48.8014, 2.1304);
    near(findLocations('geo:48.8014,2.1304?z=15').single, 48.8014, 2.1304);
  });

  test('a message with two positions gives both, each with its excerpt', () {
    final r = findLocations('Équipe 1 au 48.80145, 2.13047 ; équipe 2 : 48°48\'10" N 2°07\'50" E. Rappel.');
    expect(r.length, 2);
    near(r[0], 48.8028, 2.1306);
    near(r[1], 48.80145, 2.13047);
    expect(r[1].excerpt, contains('48.80145'));
  });

  test('a whole line in a grid format', () {
    final r = findLocations('Position :\n31U DQ 48251 06210\n');
    expect(r.length, 1);
    expect(r.single.format, 'mgrs');
  });

  test('nothing in an ordinary sentence', () {
    expect(findLocations('Réunion à 14 h 30, salle 12, avec JN18 et 3 équipes.'), isEmpty);
  });
}
