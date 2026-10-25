import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';

void main() {
  const base = AppConfig(serverUrl: 's', eventId: 'e', deviceId: 'd', tileUrl: 't', tileAttribution: 'a');
  test('palette of eight colours, white included', () {
    expect(drawingPalette.length, 8);
    expect(drawingPalette, contains(0xFFFFFFFF));
  });
  test('profile colour, red by default or when unknown', () {
    expect(defaultDrawColor(null), drawingPalette.first);
    expect(defaultDrawColor(0xFF123456), drawingPalette.first);
    expect(defaultDrawColor(0xFF43A047), 0xFF43A047);
  });
  test('kept in the stored settings', () {
    final c = base.copyWith(drawColor: 0xFF1E88E5);
    expect(AppConfig.fromStored(c.toStored(), base).drawColor, 0xFF1E88E5);
    expect(AppConfig.fromStored(base.toStored(), base).drawColor, isNull);
  });
}
