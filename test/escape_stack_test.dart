import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/ui/escape_stack.dart';

void main() {
  test('Échap closes the panel opened last, then the previous one', () {
    final e = EscapeStack();
    final closed = <String>[];
    expect(e.escape(closed.add), isFalse);
    e.sync(['teams']);
    e.sync(['teams', 'desk']);
    expect(e.top, 'desk');
    expect(e.escape(closed.add), isTrue);
    e.sync(['teams']);
    expect(e.escape(closed.add), isTrue);
    e.sync([]);
    expect(e.escape(closed.add), isFalse);
    expect(closed, ['desk', 'teams']);
  });

  test('a panel closed by its own button leaves the order', () {
    final e = EscapeStack()..sync(['routes'])..sync(['routes', 'resection'])..sync(['routes']);
    expect(e.order, ['routes']);
    e.sync(['routes', 'reference']);
    expect(e.top, 'reference');
  });
}
