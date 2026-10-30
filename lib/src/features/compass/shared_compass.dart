/// One source of heading for the whole app (card « Boussole instable »,
/// validated on 30 Oct 2026): bearing, résection, measure, navigation and the
/// map turned like the phone all read this compass. The heading comes from
/// the system, already fused and calibrated (Android rotation vector with the
/// gyroscope, iPhone Core Location), is smoothed over ~0.5 s without a jump
/// from 359° to 0°, and the accuracy says when to calibrate (figure of 8).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../platform/platform_services.dart' show compassReadings;
import 'compass_reading.dart';

/// Circular mean of [degrees] and their spread (circular standard
/// deviation, degrees); null without values.
({double mean,double spread})? circularStats(Iterable<double> degrees){
  var s=0.0,c=0.0,n=0;
  for(final d in degrees){final r=d*math.pi/180;s+=math.sin(r);c+=math.cos(r);n++;}
  if(n==0)return null;
  final mean=(math.atan2(s,c)*180/math.pi+360)%360;
  final len=math.min(1.0,math.sqrt(s*s+c*c)/n);
  final spread=len<=1e-9?180.0:math.sqrt(-2*math.log(len))*180/math.pi;
  return (mean:mean,spread:spread);
}

/// Smoothing of the shown heading: circular mean of the readings of the
/// last [window], so that 359° and 1° give 0°, not 180°.
class HeadingSmoother {
  final Duration window;
  HeadingSmoother({this.window=const Duration(milliseconds:500)});
  final _samples=<(DateTime,double)>[];
  double? add(DateTime t,double deg){
    _samples.add((t,deg));
    _samples.removeWhere((e)=>t.difference(e.$1)>window);
    return circularStats(_samples.map((e)=>e.$2))?.mean;
  }
  void clear()=>_samples.clear();
}

/// Accuracy too low for a bearing: more than 25° announced, or Android
/// status « unreliable » / « low ».
bool compassNeedsCalibration(double? accuracyDeg,int status)=>(accuracyDeg!=null&&accuracyDeg>=25)||status==0||status==1;

class SharedCompass extends ChangeNotifier {
  SharedCompass({Stream<CompassReading>? Function()? open,DateTime Function()? clock})
    :_open=open??compassReadings,_clock=clock??DateTime.now;
  static final instance=SharedCompass();

  final Stream<CompassReading>? Function() _open;
  final DateTime Function() _clock;
  int _users=0;
  StreamSubscription<CompassReading>? _sub;
  final _smoother=HeadingSmoother();
  /// Raw headings of the last seconds, for the 2 s average of a bearing.
  final _raw=<(DateTime,double)>[];

  /// Smoothed magnetic heading, null until the first valid reading.
  double? heading;
  double? accuracyDeg; int status=-1;
  /// The system says the compass must be calibrated.
  bool calibrate=false;
  bool get available=>heading!=null;

  /// Starts the compass for one more user; false without compass
  /// (computers). Each start is matched by one [stop].
  bool start(){
    _users++;
    if(_sub!=null)return true;
    Stream<CompassReading>? s;
    try{s=_open();}catch(_){s=null;}
    if(s==null)return false;
    _sub=s.listen(_on,onError:(_){});
    return true;
  }

  void stop(){
    if(_users>0)_users--;
    if(_users>0)return;
    _sub?.cancel(); _sub=null;
    heading=null; accuracyDeg=null; status=-1; calibrate=false;
    _smoother.clear(); _raw.clear();
  }

  void _on(CompassReading r){
    accuracyDeg=r.accuracyDeg; status=r.status;
    final h=r.headingDeg;
    calibrate=h==null||compassNeedsCalibration(r.accuracyDeg,r.status);
    if(h!=null&&h.isFinite&&h>=0){
      final t=_clock();
      _raw.add((t,h%360));
      _raw.removeWhere((e)=>t.difference(e.$1)>const Duration(seconds:3));
      heading=_smoother.add(t,h%360);
    }
    notifyListeners();
  }

  /// Mean of the raw headings over the next [duration] and their spread
  /// (« ± x° »), null when no reading came.
  Future<({double mean,double spread})?> average([Duration duration=const Duration(seconds:2)]) async {
    final from=_clock();
    await Future<void>.delayed(duration);
    return circularStats(_raw.where((e)=>!e.$1.isBefore(from)).map((e)=>e.$2));
  }

  /// Test hook: a reading as if it came from the system.
  @visibleForTesting void push(CompassReading r)=>_on(r);
}
