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
  // Messages
  'messages.title':'Messages · {n} en attente','messages.all':'Tous les messages','messages.broadcast':'Diffusion générale',
  'messages.direct':'Direct','messages.directHint':'Identifiant de l’agent ou de l’équipe','messages.hint':'Message court',
  'messages.send':'Envoyer','messages.photo':'Envoyer une photo','messages.takePhoto':'Prendre une photo',
  'messages.pickImage':'Choisir une image','messages.photoTooLarge':'Photo trop lourde (10 Mo au maximum)',
  'messages.photoFailed':'Photo impossible : {error}','messages.photoDefault':'Photo','messages.sendPhoto':'Envoyer la photo',
  'messages.caption':'Légende (facultative)','messages.photoUnavailable':'Photo indisponible','messages.tapRetry':'Toucher pour réessayer',
  'messages.pendingUpload':'En attente d’envoi','messages.saveFile':'Enregistrer','messages.photoSaved':'Photo enregistrée : {path}',
  'messages.photoDownloaded':'Photo téléchargée','messages.saveFailed':'Échec de l’enregistrement : {error}',
  'priority.routine':'Routine','priority.urgent':'Urgent','priority.immediate':'Immédiat',
  'ack.received':'Reçu','ack.read':'Lu','ack.accepted':'Accepté','ack.rejected':'Refusé','messages.to':'À : {to}',
  // Groups
  'groups.new':'Nouveau groupe','groups.edit':'Modifier le groupe','groups.name':'Nom','groups.description':'Description',
  'groups.listenOnly':'Écoute seule','groups.listenOnlyHelp':'Seuls les émetteurs désignés, les responsables et le PCO écrivent',
  'groups.members':'Membres (identifiants séparés par des virgules)','groups.senders':'Émetteurs désignés',
  'groups.radio':'Canal radio associé (facultatif)','groups.color':'Couleur','groups.archived':'Groupe archivé',
  'groups.delete':'Supprimer le groupe','groups.deleteConfirm':'Supprimer « {name} » ?','groups.cannotSend':'Groupe en écoute seule : seuls ses émetteurs, ses responsables et le PCO y écrivent.',
  'groups.archivedNotice':'Groupe archivé : plus aucun message.','groups.managers':'Responsables : {names}',
  'groups.listenOnlyBadge':'écoute seule',
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
  // Event list (« Choix de l'événement dans une liste »)
  'settings.eventsRefresh':'Recharger la liste des événements','settings.eventsOffline':'Pas de réseau : dernière liste connue',
  'settings.eventsEmpty':'Aucun événement ouvert sur ce serveur','settings.eventsError':'Liste indisponible ({error})',
  'settings.eventAdvanced':'Saisie avancée','settings.eventId':'Identifiant de l’événement',
  'settings.eventIdHelp':'Seulement pour un serveur ancien ou un dépannage',
  'eventState.draft':'brouillon','eventState.active':'actif','eventState.closed':'clos',
  'settings.eventUnlisted':'{id} (absent de la liste)',
  // Unsent items (« Robustesse de la synchronisation »)
  'status.unsent':'Connecté · {n} non envoyés','status.inFlight':'En attente ({n})',
  'status.eventUnknown':'Événement inconnu de ce serveur',
  'unsent.title':'Éléments non envoyés','unsent.empty':'Aucun élément non envoyé',
  'unsent.retry':'Réessayer','unsent.retryAll':'Tout réessayer','unsent.attach':'Rattacher à l’événement en cours',
  'unsent.export':'Exporter','unsent.delete':'Supprimer',
  'unsent.deleteConfirm':'Supprimer cet élément ? Il ne sera jamais envoyé. La suppression est inscrite dans le journal de l’appareil.',
  'unsent.otherEvent':'Autre événement : {event}','unsent.otherServer':'Autre serveur : {server}',
  'unsent.waitsReturn':'Partira au retour sur ce serveur et cet événement',
  'unsent.attempts':'{n} essai(s)','unsent.since':'depuis {age}','unsent.exported':'Exporté : {path}',
  'unsent.exportFailed':'Export impossible',
  'type.message':'Message','type.map_feature':'Objet cartographique','type.poi':'Point d’intérêt',
  'type.position':'Position','type.ack':'Accusé de réception',
  'change.title':'Éléments non envoyés','change.body':'{n} élément(s) non envoyé(s) vers l’événement {event} ({server}).',
  'change.sendFirst':'Envoyer d’abord','change.keep':'Garder pour plus tard',
  'change.kept':'{n} élément(s) gardé(s) pour plus tard, visibles dans « Éléments non envoyés »',
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
  'messages.title':'Messages · {n} pending','messages.all':'All messages','messages.broadcast':'General broadcast',
  'messages.direct':'Direct','messages.directHint':'Agent or team identifier','messages.hint':'Short message',
  'messages.send':'Send','messages.photo':'Send a photo','messages.takePhoto':'Take a photo',
  'messages.pickImage':'Choose an image','messages.photoTooLarge':'Photo too large (10 MB maximum)',
  'messages.photoFailed':'Photo failed: {error}','messages.photoDefault':'Photo','messages.sendPhoto':'Send the photo',
  'messages.caption':'Caption (optional)','messages.photoUnavailable':'Photo unavailable','messages.tapRetry':'Tap to retry',
  'messages.pendingUpload':'Waiting to be sent','messages.saveFile':'Save','messages.photoSaved':'Photo saved: {path}',
  'messages.photoDownloaded':'Photo downloaded','messages.saveFailed':'Saving failed: {error}',
  'priority.routine':'Routine','priority.urgent':'Urgent','priority.immediate':'Immediate',
  'ack.received':'Received','ack.read':'Read','ack.accepted':'Accepted','ack.rejected':'Refused','messages.to':'To: {to}',
  'groups.new':'New group','groups.edit':'Edit group','groups.name':'Name','groups.description':'Description',
  'groups.listenOnly':'Listen only','groups.listenOnlyHelp':'Only designated senders, managers and the command post write',
  'groups.members':'Members (comma separated identifiers)','groups.senders':'Designated senders',
  'groups.radio':'Associated radio channel (optional)','groups.color':'Colour','groups.archived':'Archived group',
  'groups.delete':'Delete the group','groups.deleteConfirm':'Delete “{name}”?','groups.cannotSend':'Listen-only group: only its senders, its managers and the command post write here.',
  'groups.archivedNotice':'Archived group: no more messages.','groups.managers':'Managers: {names}',
  'groups.listenOnlyBadge':'listen only',
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
  'settings.eventsRefresh':'Reload the event list','settings.eventsOffline':'No network: last known list',
  'settings.eventsEmpty':'No open event on this server','settings.eventsError':'List unavailable ({error})',
  'settings.eventAdvanced':'Advanced entry','settings.eventId':'Event identifier',
  'settings.eventIdHelp':'Only for an older server or troubleshooting',
  'eventState.draft':'draft','eventState.active':'active','eventState.closed':'closed',
  'settings.eventUnlisted':'{id} (not in the list)',
  'status.unsent':'Connected · {n} not sent','status.inFlight':'Pending ({n})',
  'status.eventUnknown':'Event unknown to this server',
  'unsent.title':'Items not sent','unsent.empty':'No item waiting',
  'unsent.retry':'Retry','unsent.retryAll':'Retry all','unsent.attach':'Attach to the current event',
  'unsent.export':'Export','unsent.delete':'Delete',
  'unsent.deleteConfirm':'Delete this item? It will never be sent. The deletion is written in the device journal.',
  'unsent.otherEvent':'Other event: {event}','unsent.otherServer':'Other server: {server}',
  'unsent.waitsReturn':'Will leave when back on this server and event',
  'unsent.attempts':'{n} attempt(s)','unsent.since':'for {age}','unsent.exported':'Exported: {path}',
  'unsent.exportFailed':'Export failed',
  'type.message':'Message','type.map_feature':'Map object','type.poi':'Point of interest',
  'type.position':'Position','type.ack':'Acknowledgement',
  'change.title':'Items not sent','change.body':'{n} item(s) not sent to event {event} ({server}).',
  'change.sendFirst':'Send first','change.keep':'Keep for later',
  'change.kept':'{n} item(s) kept for later, listed in « Items not sent »',
};
