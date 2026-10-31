import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/models/web_update.dart';

void main() {
  test('a different served build is an update', () {
    expect(webUpdateAvailable('main@1111111', 'main@2222222'), isTrue);
  });
  test('same build, local build or nothing served: no prompt', () {
    expect(webUpdateAvailable('main@1111111', 'main@1111111'), isFalse);
    expect(webUpdateAvailable('main@1111111', ' main@1111111\n'), isFalse);
    expect(webUpdateAvailable('', 'main@2222222'), isFalse);
    expect(webUpdateAvailable('main@1111111', null), isFalse);
    expect(webUpdateAvailable('main@1111111', ''), isFalse);
  });
  test('sarcade_build.json is read', () {
    expect(parseServedBuild({'build': 'feat/x@abc1234'}), 'feat/x@abc1234');
    expect(parseServedBuild({'other': 1}), isNull);
    expect(parseServedBuild('text'), isNull);
  });
  test('served version and the change shown before « Nouvelle version »', () {
    expect(parseServedVersion({'build': 'main@abc1234', 'version': '0.1.0+560'}), '0.1.0+560');
    expect(parseServedVersion({'build': 'main@abc1234'}), isNull);
    expect(versionChange('0.1.0+535', '0.1.0+560'), '(0.1.0+535 → 0.1.0+560) ');
    expect(versionChange('0.1.0+535', null), '');
    expect(versionChange('0.1.0+560', '0.1.0+560'), '');
  });
}
