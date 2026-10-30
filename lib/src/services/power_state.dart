/// « iPhone, forte consommation de batterie » (validated by the project
/// owner on 30 Oct 2026, 12 h 42, points A to F): one place that knows
/// whether SARCADE is on screen and whether the power-saving mode is on.
/// A) the compass is released in the background; B) the Beacon interval
/// adapts (chosen interval when moving, 60 s standing still, reduced
/// accuracy in the background on iPhone); C) « même réseau » TV check every
/// 60 s, on screen, PCO / administrator only; D) no periodic refresh in the
/// background (notifications still wake the app); E) power-saving mode
/// (Beacon every 2 min, map refreshed less often); F) « Consommation » line
/// of the Diagnostic.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../features/compass/shared_compass.dart';
import '../offline/local_store.dart';

/// Interval of the Beacon actually used: the chosen one when moving, at
/// least 60 s standing still, at least 2 min in power-saving mode.
int adaptiveIntervalS(int chosenS,{required bool moving,required bool saver})=>
  saver?math.max(chosenS,120):moving?chosenS:math.max(chosenS,60);

/// Moving: speed above 0.7 m/s, or farther than max(25 m, accuracy) from
/// the last position sent. Unknown values count as moving (no slowing down
/// without a reason).
bool isMoving({double? speedMps,double? distanceM,double? accuracyM}){
  if(speedMps!=null&&speedMps>=0&&speedMps>0.7)return true;
  if(distanceM==null)return speedMps==null||speedMps<0;
  return distanceM>math.max(25.0,accuracyM??0);
}

/// « Même réseau » TV check from the 2 s timer of the map: every 60 s,
/// SARCADE on screen, PCO or administrator only (point C).
bool shouldPollTvNearby(int tick,{required bool foreground,required bool pco})=>foreground&&pco&&tick%30==5;

/// Map redrawn by the 2 s timer: every tick, every 10 s in power-saving
/// mode, never in the background (points D and E).
bool shouldRefreshUi(int tick,{required bool foreground,required bool saver})=>foreground&&(!saver||tick%5==0);

class PowerState extends ChangeNotifier {
  static final instance=PowerState();

  /// SARCADE is on screen (resumed or briefly inactive).
  bool foreground=true;
  /// « Mode économie » of Paramètres › Affichage.
  bool saver=false;
  /// Beacon as reported by the tracking service, for the Diagnostic.
  int? trackingS; bool trackingMoving=true; bool gpsReduced=false;

  LocalStore? _store;
  AppLifecycleListener? _listener;

  void init(LocalStore store){
    _store=store;
    saver=store.preference('power_saver')=='1';
    _listener??=AppLifecycleListener(onStateChange:(s)=>setForeground(s==AppLifecycleState.resumed||s==AppLifecycleState.inactive));
  }

  void setForeground(bool v){
    if(v==foreground)return;
    foreground=v;
    SharedCompass.instance.setPaused(!v);
    notifyListeners();
  }

  Future<void> setSaver(bool v) async {
    if(v==saver)return;
    saver=v;
    notifyListeners();
    await _store?.setPreference('power_saver',v?'1':null);
  }

  void reportTracking({int? intervalS,bool moving=true,bool reduced=false}){
    trackingS=intervalS; trackingMoving=moving; gpsReduced=reduced;
  }

  @override void dispose(){_listener?.dispose();super.dispose();}
}

/// Text of the « Consommation » line (point F), pure for the tests.
String consumptionLine({required int? trackingS,required bool moving,required bool reduced,required bool compass,
    required bool saver,required String Function(String key,[Map<String,Object?> args]) t}){
  final parts=<String>[
    trackingS==null?t('power.gpsOff'):t('power.gps',{'interval':trackingS<60?'$trackingS s':'${trackingS~/60} min'})
      +(moving?'':' · ${t('power.still')}')+(reduced?' · ${t('power.reduced')}':''),
    t(compass?'power.compassOn':'power.compassOff'),
    if(saver)t('power.saverOn'),
  ];
  return parts.join(' · ');
}
