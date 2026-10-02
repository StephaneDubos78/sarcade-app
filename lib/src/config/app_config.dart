class AppConfig {
  final String serverUrl, eventId, deviceId, tileUrl, tileAttribution;
  const AppConfig({required this.serverUrl,required this.eventId,required this.deviceId,required this.tileUrl,required this.tileAttribution});
  factory AppConfig.fromEnvironment()=>const AppConfig(
    serverUrl:String.fromEnvironment('SARCADE_SERVER_URL',defaultValue:'http://localhost:8000'),
    eventId:String.fromEnvironment('SARCADE_EVENT_ID',defaultValue:'evt-demo'),
    deviceId:String.fromEnvironment('SARCADE_DEVICE_ID',defaultValue:'device-demo'),
    tileUrl:String.fromEnvironment('SARCADE_TILE_URL',defaultValue:'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    tileAttribution:String.fromEnvironment('SARCADE_TILE_ATTRIBUTION',defaultValue:'© OpenStreetMap contributors'),
  );
}
