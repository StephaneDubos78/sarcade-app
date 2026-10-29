import 'package:flutter/foundation.dart';
import 'event_settings.dart';

/// Last store version known for this phone, read by Paramètres › Diagnostic
/// and À propos (« À jour » or « Nouvelle version disponible »).
final latestRelease=ValueNotifier<StoreRelease?>(null);
