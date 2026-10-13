import '../platform/platform_services.dart';

class AppConfig {
  final String serverUrl, eventId, deviceId, tileUrl, tileAttribution;
  const AppConfig({required this.serverUrl,required this.eventId,required this.deviceId,required this.tileUrl,required this.tileAttribution});
  factory AppConfig.fromEnvironment()=>AppConfig(
    // The web app is served by the SARCADE server itself: same origin as the API.
    serverUrl:const bool.hasEnvironment('SARCADE_SERVER_URL')?const String.fromEnvironment('SARCADE_SERVER_URL'):(servingOrigin()??'http://localhost:8000'),
    eventId:const String.fromEnvironment('SARCADE_EVENT_ID',defaultValue:'evt-demo'),
    deviceId:const String.fromEnvironment('SARCADE_DEVICE_ID',defaultValue:'device-demo'),
    tileUrl:const String.fromEnvironment('SARCADE_TILE_URL',defaultValue:'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
    tileAttribution:const String.fromEnvironment('SARCADE_TILE_ATTRIBUTION',defaultValue:'© OpenStreetMap contributors'),
  );

  /// Runtime settings saved on the device override the build-time defaults.
  /// Only the operator-specific fields are stored, tile settings stay build-time.
  factory AppConfig.fromStored(Map<String,dynamic> j,AppConfig fallback)=>fallback.copyWith(
    serverUrl:j['server_url'] as String?,
    eventId:j['event_id'] as String?,
    deviceId:j['device_id'] as String?,
  );

  Map<String,dynamic> toStored()=>{'server_url':serverUrl,'event_id':eventId,'device_id':deviceId};

  AppConfig copyWith({String? serverUrl,String? eventId,String? deviceId,String? tileUrl,String? tileAttribution})=>AppConfig(
    serverUrl:serverUrl??this.serverUrl,
    eventId:eventId??this.eventId,
    deviceId:deviceId??this.deviceId,
    tileUrl:tileUrl??this.tileUrl,
    tileAttribution:tileAttribution??this.tileAttribution,
  );

  bool get isComplete=>serverUrl.trim().isNotEmpty&&eventId.trim().isNotEmpty&&deviceId.trim().isNotEmpty;

  /// Identity of the operational session, used to rebuild the map when it changes.
  String get sessionKey=>'$serverUrl|$eventId|$deviceId';
}
