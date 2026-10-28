/// « Ma position » button (requests of 26 and 27 Oct 2026): centre on the
/// device, follow it, then follow it with the map turned like the phone
/// (compass), as in Google Maps.
library;

enum MeMode { off, follow, compass }

/// Mode after a press of the button, the map being centred on the device
/// or not.
MeMode nextMeMode(MeMode mode,{required bool centred})=>switch(mode){
  MeMode.off=>centred?MeMode.follow:MeMode.off, // first press only centres
  MeMode.follow=>MeMode.compass,
  MeMode.compass=>MeMode.follow,
};

/// Smoothed heading: moves [fraction] of the way towards [target], across
/// north without a full turn (359° → 1° goes through 0°).
double smoothHeading(double? current,double target,{double fraction=0.25}){
  if(current==null)return (target%360+360)%360;
  final diff=((target-current+540)%360)-180;
  return ((current+diff*fraction)%360+360)%360;
}

/// Turning the map is worth it only past a small change (less redrawing).
bool headingChanged(double? shown,double heading,{double minDeg=2})=>
  shown==null||(((heading-shown+540)%360)-180).abs()>=minDeg;
