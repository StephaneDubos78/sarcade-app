/// « Voir sur QRZ.com » and « aprs.fi » in the sheet of an operator or a
/// station named by a callsign (card « Fiche opérateur, informations de
/// l'indicatif radioamateur », point 1, decision of 30 Oct 2026, 1 h 51):
/// the page of the callsign opens, nothing is copied nor stored.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/strings.dart';
import 'aprs_models.dart';

/// The first of [names] that looks like a callsign, else null.
String? callsignAmong(Iterable<String?> names){
  for(final n in names){if(n!=null&&looksLikeCallsign(n))return n.trim().toUpperCase();}
  return null;
}

class CallsignLinks extends StatelessWidget {
  final String callsign;
  const CallsignLinks({super.key,required this.callsign});
  Future<void> _open(String url) async {try{await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);}catch(_){/* no browser */}}
  @override Widget build(BuildContext context)=>Wrap(spacing:8,runSpacing:4,children:[
    ActionChip(key:const ValueKey('link-qrz'),avatar:const Icon(Icons.badge_outlined,size:16),label:Text(S.t('station.qrz')),
      visualDensity:VisualDensity.compact,onPressed:()=>_open(qrzUrl(callsign))),
    ActionChip(key:const ValueKey('link-aprsfi'),avatar:const Icon(Icons.public,size:16),label:const Text('aprs.fi'),
      visualDensity:VisualDensity.compact,onPressed:()=>_open(aprsFiUrl(callsign))),
  ]);
}
