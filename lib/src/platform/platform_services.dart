/// Platform services that differ between installed apps and the browser.
///
/// Installed apps (Android, iOS, Windows, Linux, macOS) use dart:io; the
/// installable web app (PWA, main channel on ChromeOS) uses browser APIs.
/// Everything else in the app is shared.
library;

export 'platform_services_io.dart'
    if (dart.library.js_interop) 'platform_services_web.dart';
