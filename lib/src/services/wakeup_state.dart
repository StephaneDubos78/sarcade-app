import 'package:flutter/foundation.dart';

/// Registration of this device for the wake-up when SARCADE is closed, set
/// by the open map; Paramètres › Notifications calls it before a test.
Future<bool> Function()? registerWakeupHook;
/// Server has the token of this device (true), refused or unavailable
/// (false), not tried yet (null).
final wakeupRegistered=ValueNotifier<bool?>(null);
