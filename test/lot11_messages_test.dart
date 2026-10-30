import 'package:flutter_test/flutter_test.dart';
import 'package:sarcade_app/src/features/messages/messages_nav.dart';

void main() {
  test('Messages in blue while its page or a conversation panel is open', () {
    expect(messagesRailSelected(deskId: 'messages', chatPeer: null), isTrue);
    expect(messagesRailSelected(deskId: null, chatPeer: 'TEL-02'), isTrue);
    expect(messagesRailSelected(deskId: 'files', chatPeer: null), isFalse);
    expect(messagesRailSelected(deskId: null, chatPeer: null), isFalse);
  });
}
