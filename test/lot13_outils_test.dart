import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/tools/tools_page.dart';

// Found by the cinématique test on the Android emulator (31 Oct 2026):
// the tool tiles overflowed on a narrow phone.
void main() {
  for (final width in [320.0, 360.0, 411.0, 600.0, 900.0]) {
    testWidgets('tool tiles do not overflow at $width px', (t) async {
      t.view.physicalSize = Size(width, 800); t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: ToolsPage(items: [
        for (final n in ['Weather', 'Coordinate converter', 'Routes', 'Resection'])
          ToolItem(id: n, icon: Icons.build, title: n, subtitle: 'Forecast, warnings and a long help line that takes two lines on a phone',
            color: Colors.blue, onTap: () {}),
      ])));
      expect(t.takeException(), isNull);
    });
  }
}
