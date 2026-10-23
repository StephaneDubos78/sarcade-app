# Operations on the client — v0.1

Specs: « Synchronisation client-serveur », « Suivi de position » (Beacon),
« Langues de l'application », « Mises à jour et sécurité » (vault).

- **Heartbeat** every 30 s (at the grouped-sending interval in low-bandwidth
  mode): last contact, items waiting in the Outbox and the oldest one,
  tracking state and interval, platform, version, callsign and APRS consent.
  The answer brings the event settings (kept on the device for offline
  starts), the end of the event and the minimal client version.
- **Low-bandwidth mode** (imposed by the PCO): grouped sending every
  `low_bandwidth_interval_s` (60 s by default); urgent and immediate messages
  leave at once; photos stay on the device and leave when the mode is lifted,
  messages no longer wait for their photos meanwhile.
- **Alert** when items have waited longer than `sync_alert_minutes` (5 min by
  default), with a « Send » button; the manual sync button stays.
- **Beacon** (« Suivi de position »): on/off and interval among 10 s, 30 s,
  1, 2, 5, 10 min within the PCO bounds; the last GPS fix is sent at each
  interval (not repeated without a new fix). Required by the PCO → started
  and cannot be stopped; stopped at the end of the event. Choice kept per
  event.
- **Minimal version**: `/clients/check` at start, then with each heartbeat;
  banner when invited (deadline 2 h) or deferred to the end of the event;
  blocking page when required, with the download of the package offered by
  the local server (Windows, AppImage, APK).
- **Languages**: French and English, device language by default, English for
  any other language; choice in the settings. The new screens and the main
  map page are translated; the other screens follow.
