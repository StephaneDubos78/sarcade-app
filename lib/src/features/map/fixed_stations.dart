/// « Équipes, stations APRS fixes (iGates, relais) » (validated on 30 Oct
/// 2026, 12 h 52): an APRS station is fixed by its symbol (iGate, relay,
/// house, weather), its SSID (-10 iGate, -1 to -3 relay or fixed) or when
/// it does not move (under 50 m over several hours); a classification
/// forced by hand in the sheet wins. Fixed stations: folded section at the
/// bottom of Équipes, discreet symbol without trace on the map, switch
/// « Stations fixes » in Affichage (off by default).
library;

import 'package:latlong2/latlong.dart';

import '../../models/position.dart';
import 'drawing/geometry.dart' as geo;
import 'stations.dart';

/// Symbols of stations that do not move.
const fixedSymbolKinds={'igate','digipeater','repeater','house','weather'};
/// Symbols of vehicles and people: the SSID does not make them fixed.
const mobileSymbolKinds={'car','truck','van','jeep','motorcycle','bike','person','ambulance','fire','boat','aircraft','helicopter','balloon','rv','bus','train'};
/// Movement threshold and observation time.
const fixedMoveM=50.0;
const fixedAfter=Duration(hours:3);

/// SSID of a callsign (« F4ABC-10 » → 10), null without SSID.
int? ssidOf(String? callsign){
  if(callsign==null)return null;
  final i=callsign.lastIndexOf('-');
  return i<0?null:int.tryParse(callsign.substring(i+1));
}

/// First position seen of each station and whether it moved since (more
/// than 50 m), kept for the session.
class MovementTracker {
  final Map<String,({LatLng at,DateTime since})> _anchor={};
  final Set<String> _moved={};
  void observe(SarcadePosition p){
    final at=LatLng(p.lat,p.lon); final a=_anchor[p.deviceId];
    if(a==null){_anchor[p.deviceId]=(at:at,since:p.time.toUtc());return;}
    if(p.time.toUtc().isBefore(a.since))_anchor[p.deviceId]=(at:a.at,since:p.time.toUtc());
    if(geo.distanceM(a.at,at)>fixedMoveM)_moved.add(p.deviceId);
  }
  bool moved(String id)=>_moved.contains(id);
  /// Seen for at least [fixedAfter] without moving.
  bool still(String id,DateTime now){final a=_anchor[id];return a!=null&&!_moved.contains(id)&&now.difference(a.since)>=fixedAfter;}
}

/// Fixed or mobile: [forced] (« f » / « m ») wins, then the movement,
/// the symbol, the SSID and the absence of movement.
bool isFixedStation(SarcadePosition p,{String? forced,bool moved=false,bool still=false}){
  if(!p.isAprs)return false;
  if(forced=='f')return true;
  if(forced=='m')return false;
  if(moved||(p.speedMps??0)>1)return false;
  final kind=aprsSymbol(p.aprsSymbol).kind;
  if(fixedSymbolKinds.contains(kind))return true;
  final ssid=ssidOf(p.callsign??p.deviceId.replaceFirst('aprs:',''));
  if(!mobileSymbolKinds.contains(kind)&&(ssid==10||(ssid!=null&&ssid>=1&&ssid<=3)))return true;
  return still;
}

/// Forced classifications kept on the device, « id=f|id=m ».
Map<String,String> parseForced(String? v){
  final out=<String,String>{};
  for(final s in (v??'').split('|')){
    final i=s.lastIndexOf('=');
    if(i>0&&(s.substring(i+1)=='f'||s.substring(i+1)=='m'))out[s.substring(0,i)]=s.substring(i+1);
  }
  return out;
}
String? encodeForced(Map<String,String> m)=>m.isEmpty?null:(m.keys.toList()..sort()).map((k)=>'$k=${m[k]}').join('|');
