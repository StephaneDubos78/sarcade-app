import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/services/notification_service_io.dart';

// Card « Client Windows : écran gris au démarrage » (31 Oct 2026): the
// Windows notification plugin stops an elevated SARCADE.
void main() {
  test('elevation check never throws; false outside Windows', () {
    // The Windows machines of the CI run as administrator: true there.
    final elevated = windowsElevated();
    if (!Platform.isWindows) expect(elevated, isFalse);
  });

  test('notifications reported off when Windows refused them', () async {
    NotificationService.windowsUnavailable = 'admin';
    expect(await NotificationService().permissionGranted(), isFalse);
    NotificationService.windowsUnavailable = null;
  });
}
