import 'package:flutter/foundation.dart';

class NotificationService {
  Future<void> initialize() async {}
  Future<void> message({required String title,required String body,required String priority}) async {
    // V0.1 portable fallback. Native notifications are added per platform after
    // Android/iOS runners and permissions are committed.
    debugPrint('SARCADE notification [$priority] $title: $body');
  }
}
