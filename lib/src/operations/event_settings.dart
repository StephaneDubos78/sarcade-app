/// Operational settings of the event, set by the PCO and received with each
/// heartbeat (notes « Synchronisation client-serveur », « Suivi de
/// position »). Pure code, testable without Flutter.
library;

/// Intervals offered to operators, in seconds (same list as the server).
const trackingIntervals=[10,30,60,120,300,600];

class EventSettings {
  final bool lowBandwidth, trackingRequired, eventEnded;
  final int lowBandwidthIntervalS, syncAlertMinutes, trackingDefaultS, trackingMinS, trackingMaxS;
  final String basemap;
  final Map<String,dynamic> raw;
  const EventSettings({this.lowBandwidth=false,this.trackingRequired=false,this.eventEnded=false,
    this.lowBandwidthIntervalS=60,this.syncAlertMinutes=5,this.trackingDefaultS=30,this.trackingMinS=10,
    this.trackingMaxS=600,this.basemap='osm',this.raw=const {}});

  static int _int(Object? v,int fallback)=>v is num?v.toInt():fallback;

  /// From the heartbeat answer: `settings`, `ended_at`, `tracking_required`.
  factory EventSettings.fromHeartbeat(Map<String,dynamic> j){
    final s=j['settings'] is Map?Map<String,dynamic>.from(j['settings'] as Map):<String,dynamic>{};
    return EventSettings(
      lowBandwidth:s['low_bandwidth']==true,
      trackingRequired:j['tracking_required']==true,
      eventEnded:j['ended_at']!=null,
      lowBandwidthIntervalS:_int(s['low_bandwidth_interval_s'],60),
      syncAlertMinutes:_int(s['sync_alert_minutes'],5),
      trackingDefaultS:_int(s['tracking_default_interval_s'],30),
      trackingMinS:_int(s['tracking_min_interval_s'],10),
      trackingMaxS:_int(s['tracking_max_interval_s'],600),
      basemap:(s['basemap'] as String?)??'osm',
      raw:s,
    );
  }

  Map<String,dynamic> toJson()=>{'settings':raw,'tracking_required':trackingRequired,
    'ended_at':eventEnded?'ended':null};

  /// Intervals the operator may choose within the PCO bounds.
  List<int> get allowedIntervals{
    final list=trackingIntervals.where((i)=>i>=trackingMinS&&i<=trackingMaxS).toList();
    return list.isEmpty?[clampInterval(trackingDefaultS)]:list;
  }

  int clampInterval(int s)=>s<trackingMinS?trackingMinS:(s>trackingMaxS?trackingMaxS:s);

  /// Modules of the event (card « Séparer le Core et les modules », 31 Oct
  /// 2026): ADRASEC when the server does not say (older servers, events
  /// created before, first start before the heartbeat).
  List<String> get modules=>eventModules(raw);
  bool moduleOn(String id)=>modules.contains(id);
}

/// Modules of event settings ([raw] of [EventSettings], or `settings` of
/// GET /events/{id}).
List<String> eventModules(Map<String,dynamic>? settings){
  final m=settings?['modules'];
  return m is List?m.whereType<String>().toList():const ['adrasec'];
}

/// Event models offered when the PCO creates an event, and the modules
/// each turns on (server: sarcade.modules.TEMPLATES).
const eventKinds=['exercise','sater','mission','race','family','friends'];
const _kindModules={'family':<String>[],'friends':<String>[],'exercise':['adrasec'],'sater':['adrasec'],'mission':['adrasec'],'race':['race']};
List<String> modulesOfKind(String kind)=>_kindModules[kind]??const ['adrasec'];

/// Modules offered to the PCO, in display order (same list as the server).
const eventModuleIds=['adrasec','race'];

/// Alert shown when items have waited in the Outbox longer than the PCO
/// threshold (5 minutes by default). Null when nothing is late.
({int count,int minutes})? syncAlert(List<Map<String,dynamic>> pending,DateTime now,int thresholdMinutes){
  final oldest=oldestPending(pending);
  if(oldest==null)return null;
  final waited=now.toUtc().difference(oldest.toUtc());
  if(waited.inMinutes<thresholdMinutes)return null;
  return (count:pending.length,minutes:waited.inMinutes);
}

DateTime? oldestPending(List<Map<String,dynamic>> pending){
  DateTime? oldest;
  for(final op in pending){
    final t=DateTime.tryParse('${op['client_time']}');
    if(t!=null&&(oldest==null||t.isBefore(oldest)))oldest=t;
  }
  return oldest;
}

/// Messages sent at once even in low-bandwidth mode (decision of 10 Oct
/// 2026): urgent and immediate. Everything else waits for the grouped send.
bool isUrgentOperation(Map<String,dynamic> op){
  if(op['object_type']!='message')return false;
  final p=op['payload'];
  final priority=p is Map?p['priority']:null;
  return priority=='urgent'||priority=='immediate';
}

/// Minimal client version (note « Mises à jour et sécurité »).
enum UpdateStatus{ok,invited,deferred,required}

class ClientUpdate {
  final UpdateStatus status; final String? minVersion; final DateTime? deadline;
  final String? packageUrl, packageVersion, packageSha256;
  /// Last version published on the store of this phone (Google Play,
  /// TestFlight), given by the server; never an obligation.
  final StoreRelease? latest;
  const ClientUpdate({this.status=UpdateStatus.ok,this.minVersion,this.deadline,this.packageUrl,this.packageVersion,this.packageSha256,this.latest});

  factory ClientUpdate.fromJson(Map<String,dynamic>? j){
    if(j==null)return const ClientUpdate();
    final status=switch(j['status']){'invited'=>UpdateStatus.invited,'deferred'=>UpdateStatus.deferred,
      'required'=>UpdateStatus.required,_=>UpdateStatus.ok};
    final pkg=j['package'] is Map?Map<String,dynamic>.from(j['package'] as Map):null;
    return ClientUpdate(status:status,minVersion:j['min_version'] as String?,
      deadline:j['deadline']==null?null:DateTime.tryParse('${j['deadline']}'),
      packageUrl:pkg?['url'] as String?,packageVersion:pkg?['version'] as String?,packageSha256:pkg?['sha256'] as String?,
      latest:StoreRelease.fromJson(j['latest']));
  }

  /// Version to install: the package offered by the local server, or the minimum.
  String get targetVersion=>packageVersion??minVersion??'';
}

/// Version published on Google Play or TestFlight (« client_update.latest »).
class StoreRelease {
  final String version; final int? build; final String? url;
  const StoreRelease({required this.version,this.build,this.url});
  static StoreRelease? fromJson(Object? j){
    if(j is! Map||j['version'] is! String||(j['version'] as String).isEmpty)return null;
    return StoreRelease(version:j['version'] as String,build:(j['build'] as num?)?.toInt(),url:j['url'] as String?);
  }
  /// Newer than the running application: version first, then build number.
  bool newerThan(String version,String build){
    List<int> parts(String v)=>[for(final p in v.split(RegExp(r'[-+]')).first.split('.'))int.tryParse(RegExp(r'^\d*').stringMatch(p)??'')??0];
    final a=parts(this.version), b=parts(version);
    for(var i=0;i<3;i++){
      final x=i<a.length?a[i]:0, y=i<b.length?b[i]:0;
      if(x!=y)return x>y;
    }
    return (this.build??0)>(int.tryParse(build)??0);
  }
}

/// Platform name sent to the server, matching its client packages.
String platformName({required bool isWeb,required String targetPlatform}){
  if(isWeb)return 'web';
  return switch(targetPlatform){'android'=>'android','iOS'=>'ios','windows'=>'windows','linux'=>'linux',
    'macOS'=>'macos',_=>targetPlatform};
}

/// Platform of the client package distributed by the local server.
String? packagePlatform(String platform)=>switch(platform){'windows'=>'windows','linux'=>'appimage',
  'android'=>'apk',_=>null};

/// Callsign check, same rule as the server (« F4ABC », « F4ABC-7 »).
bool validCallsign(String v)=>RegExp(r'^[A-Z0-9]{1,9}(-[A-Z0-9]{1,2})?$').hasMatch(v.trim().toUpperCase());
