/// « Écrans TV, validation automatique depuis le même réseau » (validated
/// on 30 Oct 2026, 2 h 33): a TV showing its code is noted by the server
/// with its public address; any participant of the event behind the same
/// address (decision of 30 Oct 2026, 13 h 19, formerly PCO and
/// administrators only) gets « Un écran demande à se connecter sur votre réseau (code
/// …). Autoriser ? ». Nothing is approved without a touch; the code is
/// always shown; QR code and typed code stay. Channel: the timer of the map
/// page asks the server every 60 s, SARCADE on screen only (battery card,
/// 30 Oct 2026; no new real-time message).
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';

/// Lot 11 (30 Oct 2026, 16 h 27, high priority): the « Écran à proximité »
/// dialog opened over the QR scanner on iPhone and no button answered any
/// more. Rules: 1) no dialog while a pairing (scan, typed code, name) or a
/// full-screen view (camera, photo) is open; 2) a code paired by scan or by
/// hand is never offered again; 3) the dialog opens on the root navigator,
/// above everything; 4) after « Ignorer », the same TV is not offered again
/// for 5 minutes.
class TvNearbyGate {
  TvNearbyGate._();
  static int _holds=0;
  static final Map<String,DateTime> _quietUntil={};
  static final Set<String> _handled={};
  static const ignoreDelay=Duration(minutes:5);

  /// True while a scan, a pairing or a full-screen view is open.
  static bool get suspended=>_holds>0;
  static void hold()=>_holds++;
  static void release(){if(_holds>0)_holds--;}

  /// Runs [action] with the dialog suspended (scan, pairing, camera).
  static Future<T> during<T>(Future<T> Function() action) async {
    hold();
    try{return await action();}finally{release();}
  }

  /// Code approved on this device (QR scanned, typed code, « Autoriser »).
  static void handled(String code)=>_handled.add(code.toUpperCase());
  /// « Ignorer »: quiet for [ignoreDelay].
  static void ignored(String code,DateTime now)=>_quietUntil[code.toUpperCase()]=now.add(ignoreDelay);

  static List<String> toOffer(List<String> nearby,DateTime now)=>tvCodesToOffer(nearby,_handled,_quietUntil,now);

  /// Tests only.
  static void reset(){_holds=0;_quietUntil.clear();_handled.clear();}
}

/// Codes to offer now: not handled on this device, not ignored less than
/// 5 minutes ago, each code once per round.
List<String> tvCodesToOffer(List<String> nearby,Set<String> handled,Map<String,DateTime> quietUntil,DateTime now){
  final out=<String>[];
  for(final raw in nearby){
    final c=raw.toUpperCase();
    if(handled.contains(c)||out.contains(c))continue;
    final until=quietUntil[c];
    if(until!=null&&now.isBefore(until))continue;
    out.add(c);
  }
  return out;
}

class TvNearbyWatcher {
  final SarcadeApi api;
  TvNearbyWatcher(this.api);
  bool _busy=false;

  Future<void> check(BuildContext context,String eventId) async {
    if(_busy||TvNearbyGate.suspended)return;
    _busy=true;
    try{
      final codes=TvNearbyGate.toOffer(await api.tvNearby(),DateTime.now());
      for(final code in codes){
        // A scan or a pairing may have started meanwhile.
        if(!context.mounted||TvNearbyGate.suspended)return;
        final ok=await showDialog<bool>(context:context,useRootNavigator:true,builder:(c)=>AlertDialog(key:const ValueKey('tv-nearby'),
          icon:const Icon(Icons.tv),title:Text(S.t('tv.nearbyTitle')),content:Text(S.t('tv.nearby',{'code':code})),
          actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('tv.nearbyNo'))),
            FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('tv.nearbyYes')))]));
        if(ok!=true){TvNearbyGate.ignored(code,DateTime.now());continue;}
        TvNearbyGate.handled(code);
        if(!context.mounted)return;
        String key='tv.done';
        try{await api.approveDisplay(code,eventId);}
        on SarcadeHttpException catch(e){key=e.statusCode==401||e.statusCode==403?'tv.signIn':'tv.unknownCode';}
        catch(_){key='event.offline';}
        if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(key))));
      }
    }catch(_){
      // Offline or older server: nothing offered.
    }finally{
      _busy=false;
    }
  }
}
