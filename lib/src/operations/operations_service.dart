import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/version.dart';
import '../offline/local_store.dart';
import '../offline/sync_service.dart';
import '../services/sarcade_api.dart';
import 'event_settings.dart';

/// Heartbeat of the device (note « Synchronisation client-serveur »): tells
/// the PCO the last contact, the items waiting in the Outbox and the tracking
/// state, and brings back the event settings, the end of the event and the
/// minimal client version. Works offline: the last settings are kept.
class OperationsService extends ChangeNotifier {
  final SarcadeApi api; final LocalStore store; final OfflineSyncService sync;
  final String eventId, deviceId, platform;
  /// Current tracking state and operator settings, read at each heartbeat.
  final ({bool enabled,int intervalS}) Function() tracking;
  final ({String callsign,bool aprsTxConsent}) Function() operator;

  EventSettings settings=const EventSettings();
  ClientUpdate update=const ClientUpdate();
  DateTime? lastContact;
  int? serverTrackingIntervalS;
  Timer? _timer;
  bool _busy=false;

  OperationsService({required this.api,required this.store,required this.sync,required this.eventId,
    required this.deviceId,required this.platform,required this.tracking,required this.operator}){
    final cached=store.eventSettings(eventId);
    if(cached!=null){settings=EventSettings.fromHeartbeat(cached);_applyToSync();}
  }

  void start(){
    _checkClient();
    beat();
    _schedule();
  }

  /// Heartbeat every 30 s, or at the grouped-sending interval in
  /// low-bandwidth mode so that the link is not loaded more than needed.
  void _schedule(){
    _timer?.cancel();
    final s=settings.lowBandwidth?settings.lowBandwidthIntervalS:30;
    _timer=Timer.periodic(Duration(seconds:s),(_)=>beat());
  }

  Future<void> beat() async {
    if(_busy)return;
    _busy=true;
    try{
      final pending=store.pending();
      final t=tracking(); final o=operator();
      final answer=await api.heartbeat(eventId,deviceId,{
        'label':deviceId,'platform':platform,'app_version':appVersion,
        'pending_count':pending.length,
        'oldest_pending_at':oldestPending(pending)?.toUtc().toIso8601String(),
        'tracking_enabled':t.enabled,'tracking_interval_s':t.intervalS,
        'callsign':o.callsign.trim().toUpperCase(),
        'aprs_tx_consent':o.aprsTxConsent,
      });
      final wasLow=settings.lowBandwidth, wasInterval=settings.lowBandwidthIntervalS;
      settings=EventSettings.fromHeartbeat(answer);
      serverTrackingIntervalS=(answer['tracking_interval_s'] as num?)?.toInt();
      if(answer['client_update'] is Map)update=ClientUpdate.fromJson(Map<String,dynamic>.from(answer['client_update'] as Map));
      await _saveOrganization(answer['organization']);
      lastContact=DateTime.now().toUtc();
      await store.saveEventSettings(eventId,settings.toJson());
      _applyToSync();
      if(wasLow!=settings.lowBandwidth||wasInterval!=settings.lowBandwidthIntervalS)_schedule();
      notifyListeners();
    }catch(_){
      // Offline is an expected state: the last known settings stay in force.
    }finally{
      _busy=false;
    }
  }

  Future<void> _checkClient() async {
    try{
      final j=await api.clientCheck(deviceId,platform,appVersion);
      update=ClientUpdate.fromJson(j);
      await _saveOrganization(j['organization']);
      notifyListeners();
    }catch(_){/* checked again with the heartbeats */}
  }

  /// Navigation app chosen by the organisation (« Open in… »), kept offline.
  Future<void> _saveOrganization(Object? organization) async {
    if(organization is! Map||organization['navigation'] is! Map)return;
    final nav=organization['navigation'] as Map;
    await store.setPreference('nav_app','${nav['app']??'operator'}');
    await store.setPreference('nav_hide_tracking',nav['hide_tracking_apps']==true?'1':null);
  }

  void _applyToSync()=>sync.setLowBandwidth(settings.lowBandwidth,intervalS:settings.lowBandwidthIntervalS);

  @override void dispose(){_timer?.cancel();super.dispose();}
}
