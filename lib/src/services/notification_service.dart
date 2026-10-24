/// System notifications: messages addressed to the terminal, urgent and
/// immediate ones with the highest priority, weather warnings.
///
/// Installed apps (Android, iOS, Windows, Linux, macOS) use
/// flutter_local_notifications; the web app (PWA, ChromeOS) uses the browser
/// Notification API.
library;

export 'notification_service_io.dart'
    if (dart.library.js_interop) 'notification_service_web.dart';
