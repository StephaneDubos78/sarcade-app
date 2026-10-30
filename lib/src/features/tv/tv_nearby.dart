/// « Écrans TV, validation automatique depuis le même réseau » (validated
/// on 30 Oct 2026, 2 h 33): a TV showing its code is noted by the server
/// with its public address; a PCO or an administrator behind the same
/// address gets « Un écran demande à se connecter sur votre réseau (code
/// …). Autoriser ? ». Nothing is approved without a touch; the code is
/// always shown; QR code and typed code stay. Channel: the timer of the map
/// page asks the server every 20 s (no new real-time message).
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/sarcade_api.dart';

/// Codes not offered yet: each code is offered once on this device.
List<String> tvCodesToOffer(List<String> nearby,Set<String> offered)=>[for(final c in nearby)if(!offered.contains(c))c];

class TvNearbyWatcher {
  final SarcadeApi api;
  TvNearbyWatcher(this.api);
  final Set<String> _offered={};
  bool _busy=false;

  Future<void> check(BuildContext context,String eventId) async {
    if(_busy)return;
    _busy=true;
    try{
      final codes=tvCodesToOffer(await api.tvNearby(),_offered);
      for(final code in codes){
        _offered.add(code);
        if(!context.mounted)return;
        final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(key:const ValueKey('tv-nearby'),
          icon:const Icon(Icons.tv),title:Text(S.t('tv.nearbyTitle')),content:Text(S.t('tv.nearby',{'code':code})),
          actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(S.t('tv.nearbyNo'))),
            FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(S.t('tv.nearbyYes')))]));
        if(!context.mounted)return;
        if(ok!=true)continue;
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
