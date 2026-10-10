/// Languages of the application (note « Langues de l'application »):
/// French and English, English as the fallback for any other language and
/// for a text not yet translated. Plain maps, no code generation, so that
/// adding a language is adding a map.
library;

typedef Texts=Map<String,String>;

class S {
  static const supported=['fr','en'];
  static String _lang='fr';
  static String get lang=>_lang;

  /// [choice]: 'fr', 'en', or 'system' (language of the device).
  static void setLanguage(String? choice,{String? systemLanguage}){
    final code=(choice==null||choice=='system')?(systemLanguage??'fr'):choice;
    _lang=supported.contains(code)?code:'en';
  }

  /// Translated text; `{name}` placeholders are replaced by [args].
  static String t(String key,[Map<String,Object?> args=const {}]){
    var text=_texts[_lang]?[key]??_texts['en']![key]??key;
    args.forEach((k,v){text=text.replaceAll('{$k}','${v??''}');});
    return text;
  }

  static final Map<String,Texts> _texts={'fr':_fr,'en':_en};
}

const Texts _fr={
  // General
  'app.title':'SARCADE',
  'common.cancel':'Annuler','common.ok':'OK','common.save':'Enregistrer','common.close':'Fermer',
  'common.retry':'Réessayer','common.copy':'Copier','common.copied':'Copié',
  'status.connecting':'Connexion…','status.connected':'Connecté','status.offline':'Hors connexion',
  'status.realtimeUnavailable':'Temps réel indisponible','status.pending':'{n} attente',
  // Map page
  'map.sync':'Synchroniser','map.messages':'Messages','map.menu':'Menu','map.fit':'Cadrer les opérateurs',
  'map.operators':'Opérateurs','map.references':'Référentiel radio','map.files':'Fichiers',
  'map.logbook':'Main courante','map.settings':'Paramètres',
  // Sync and low-bandwidth mode
  'sync.alert':'{n} élément(s) non envoyé(s) depuis {min} min','sync.now':'Envoyer',
  'lowband.on':'Liaison faible imposée par le PCO : envoi groupé toutes les {s} s, photos en attente',
  'lowband.photosHeld':'{n} photo(s) en attente de la levée de la liaison faible',
  // Event
  'event.ended':'Événement terminé','event.endedDetail':'Le suivi de position est arrêté.',
  // Tracking (Beacon)
  'tracking.title':'Suivi de position','tracking.start':'Suivi de position','tracking.stop':'Arrêter le suivi',
  'tracking.interval':'Envoi toutes les {interval}','tracking.required':'Suivi de position demandé par le PCO',
  'tracking.permission':'Localisation non autorisée ou indisponible','tracking.everySeconds':'{n} s',
  'tracking.everyMinutes':'{n} min','tracking.on':'Suivi actif · {interval}','tracking.off':'Suivi arrêté',
  'tracking.requiredLocked':'Le PCO demande le suivi de position pendant cet événement.',
  // Client updates
  'update.invited':'Nouvelle version {version} : mise à jour à faire avant {deadline}',
  'update.deferred':'Mise à jour obligatoire vers {version} à la fin de l’événement',
  'update.required':'Mise à jour obligatoire','update.requiredDetail':'Cette version ({current}) n’est plus acceptée par le serveur. Installe la version {version} pour te reconnecter.',
  'update.download':'Télécharger la mise à jour','update.downloaded':'Mise à jour téléchargée',
  'update.downloadFailed':'Téléchargement impossible','update.store':'Mets l’application à jour depuis le magasin d’applications ou demande le fichier au PCO.',
  // Settings
  'settings.title':'Paramètres','settings.firstRun':'Configuration SARCADE',
  'settings.intro':'Avant de commencer, indique le serveur SARCADE et ton identifiant pour cet événement.',
  'settings.server':'Serveur','settings.serverHelp':'Adresse du serveur sur le réseau local, pas localhost',
  'settings.event':'Événement','settings.device':'Identifiant du terminal',
  'settings.deviceHelp':'Unique par opérateur, affiché sur la carte du PCO',
  'settings.required':'Champ obligatoire','settings.urlExpected':'Adresse attendue : http://IP:8000',
  'settings.language':'Langue','settings.languageSystem':'Langue de l’appareil',
  'settings.callsign':'Indicatif radio (facultatif)','settings.callsignHelp':'Relie tes positions APRS à ce terminal',
  'settings.aprsConsent':'Retransmettre ma position sur la radio locale (APRS)',
  'settings.aprsConsentHelp':'Seulement si le PCO active la retransmission radio',
  'settings.callsignInvalid':'Indicatif invalide (ex. F4ABC ou F4ABC-7)',
};

const Texts _en={
  'app.title':'SARCADE',
  'common.cancel':'Cancel','common.ok':'OK','common.save':'Save','common.close':'Close',
  'common.retry':'Retry','common.copy':'Copy','common.copied':'Copied',
  'status.connecting':'Connecting…','status.connected':'Connected','status.offline':'Offline',
  'status.realtimeUnavailable':'Real time unavailable','status.pending':'{n} pending',
  'map.sync':'Synchronise','map.messages':'Messages','map.menu':'Menu','map.fit':'Fit operators',
  'map.operators':'Operators','map.references':'Radio directory','map.files':'Files',
  'map.logbook':'Logbook','map.settings':'Settings',
  'sync.alert':'{n} item(s) not sent for {min} min','sync.now':'Send',
  'lowband.on':'Low-bandwidth mode set by the command post: grouped sending every {s} s, photos on hold',
  'lowband.photosHeld':'{n} photo(s) waiting for the end of the low-bandwidth mode',
  'event.ended':'Event closed','event.endedDetail':'Position tracking has stopped.',
  'tracking.title':'Beacon','tracking.start':'Beacon','tracking.stop':'Stop beacon',
  'tracking.interval':'Send every {interval}','tracking.required':'Beacon required by the command post',
  'tracking.permission':'Location not allowed or unavailable','tracking.everySeconds':'{n} s',
  'tracking.everyMinutes':'{n} min','tracking.on':'Beacon on · {interval}','tracking.off':'Beacon off',
  'tracking.requiredLocked':'The command post requires the beacon during this event.',
  'update.invited':'New version {version}: update before {deadline}',
  'update.deferred':'Update to {version} required at the end of the event',
  'update.required':'Update required','update.requiredDetail':'This version ({current}) is no longer accepted by the server. Install version {version} to reconnect.',
  'update.download':'Download the update','update.downloaded':'Update downloaded',
  'update.downloadFailed':'Download failed','update.store':'Update the application from the app store or ask the command post for the file.',
  'settings.title':'Settings','settings.firstRun':'SARCADE setup',
  'settings.intro':'Before starting, enter the SARCADE server and your identifier for this event.',
  'settings.server':'Server','settings.serverHelp':'Address of the server on the local network, not localhost',
  'settings.event':'Event','settings.device':'Terminal identifier',
  'settings.deviceHelp':'Unique per operator, shown on the command post map',
  'settings.required':'Required','settings.urlExpected':'Expected address: http://IP:8000',
  'settings.language':'Language','settings.languageSystem':'Device language',
  'settings.callsign':'Radio callsign (optional)','settings.callsignHelp':'Links your APRS positions to this terminal',
  'settings.aprsConsent':'Relay my position on local radio (APRS)',
  'settings.aprsConsentHelp':'Only if the command post enables radio relay',
  'settings.callsignInvalid':'Invalid callsign (e.g. F4ABC or F4ABC-7)',
};
