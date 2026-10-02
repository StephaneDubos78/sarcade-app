class AppConfig {
  final String serverUrl, eventId, deviceId;
  const AppConfig({required this.serverUrl, required this.eventId, required this.deviceId});
  factory AppConfig.fromEnvironment() => const AppConfig(
    serverUrl: String.fromEnvironment('SARCADE_SERVER_URL', defaultValue: 'http://localhost:8000'),
    eventId: String.fromEnvironment('SARCADE_EVENT_ID', defaultValue: 'evt-demo'),
    deviceId: String.fromEnvironment('SARCADE_DEVICE_ID', defaultValue: 'device-demo'),
  );
}
