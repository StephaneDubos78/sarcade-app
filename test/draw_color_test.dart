import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/config/app_config.dart';
import 'package:sarcade_app/src/features/map/drawing/drawing_controller.dart';

void main() {
  const base = AppConfig(serverUrl: 's', eventId: 'e', deviceId: 'd', tileUrl: 't', tileAttribution: 'a');
  test('palette of sixteen distinct colours, white included', () {
    expect(drawingPalette.length, 16);
    expect(drawingPalette.toSet().length, 16);
    expect(drawingPalette, contains(0xFFFFFFFF));
  });
  test('profile colour: red by default, any chosen colour kept (« Autre couleur »)', () {
    expect(defaultDrawColor(null), drawingPalette.first);
    expect(defaultDrawColor(0xFF123456), 0xFF123456);
    expect(defaultDrawColor(0xFF43A047), 0xFF43A047);
  });
  test('automatic colour: the least used by the others, never white or black', () {
    expect(autoColor([]), drawingPalette.first);
    expect(autoColor([0xFFE53935]), drawingPalette[1]);
    final c = autoColor([for (final x in drawingPalette) x]);
    expect(c == 0xFFFFFFFF || c == 0xFF212121, isFalse);
  });
  test('kept in the stored settings', () {
    final c = base.copyWith(drawColor: 0xFF1E88E5);
    expect(AppConfig.fromStored(c.toStored(), base).drawColor, 0xFF1E88E5);
    expect(AppConfig.fromStored(base.toStored(), base).drawColor, isNull);
  });
}
