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
  // Routes
  'routes.title':'Routes','routes.refresh':'Actualiser','routes.new':'Nouvelle route','routes.empty':'Aucune route pour cet événement.',
  'routes.points':'points','routes.assigned':'affectée','routes.assignedTo':'Affectée à {name}','routes.addPoints':'Ajouter des points',
  'routes.stopAdding':'Terminer les points','routes.assign':'Affecter','routes.unassigned':'Non affectée','routes.computeLegs':'Calculer les tronçons',
  'routes.delete':'Supprimer','routes.deleteConfirm':'Supprimer la route « {name} » ?','routes.readOnly':'Route affectée : seuls son auteur et le PCO la modifient.',
  'routes.tapToAdd':'Touche la carte pour ajouter les points dans l’ordre.','routes.leg':'Tronçon','routes.cumulative':'Cumul','routes.pending':'calcul en attente',
  'routes.markPassage':'Marquer le passage','routes.passageRecorded':'Passage enregistré à {name}','routes.report':'Signaler impraticable',
  'routes.reportReason':'Pourquoi ce point est-il impraticable ?','routes.reported':'Signalement envoyé au PCO','routes.reportFailed':'Signalement impossible hors connexion',
  'routes.editPoint':'Modifier le point','routes.up':'Monter','routes.down':'Descendre','routes.deletePoint':'Supprimer le point',
  'routes.pointType':'Type','routes.legMode':'Tracé du tronçon','routes.radius':'Rayon d’approche : {m} m','routes.comment':'Commentaire',
  'routes.profile':'Profil','routes.profile.foot':'À pied','routes.profile.vehicle':'Véhicule',
  'routes.leg.straight':'Ligne droite','routes.leg.paths':'Par les chemins','routes.gpxSaved':'GPX enregistré','routes.gpxFailed':'Export GPX impossible hors connexion',
  'routes.menu':'Routes et navigation',
  'waypoint.start':'Départ','waypoint.pass':'Passage','waypoint.checkpoint':'Point de contrôle','waypoint.supply':'Ravitaillement','waypoint.finish':'Arrivée',
  'closures.title':'Routes coupées','closures.new':'Couper une route','closures.active':'Coupée','closures.lifted':'Rouverte',
  'closures.lift':'Rouvrir','closures.restore':'Recouper','closures.label':'Nom de la coupure (ex. Pont de la D30 inondé)',
  'closures.drawHelp':'Touche la carte pour tracer la route coupée, puis Terminer.','closures.finish':'Terminer','closures.cancel':'Annuler',
  // Navigation
  'nav.goHere':'Naviguer jusqu’ici','nav.to':'Vers {label}','nav.computing':'Calcul de l’itinéraire…','nav.eta':'arrivée {time}',
  'nav.stop':'Arrêter la navigation','nav.arrived':'Arrivé à destination','nav.shared':'Itinéraire partagé avec le PCO',
  'nav.mode.car':'En voiture','nav.mode.foot':'À pied','nav.mode.offroad':'Tout-terrain (pistes et chemins)',
  'nav.mode.straight':'Ligne droite','nav.mode.straightHelp':'Distance et cap, sans itinéraire',
  'nav.notice.engine_unavailable':'Calcul d’itinéraire indisponible : ligne droite affichée.',
  'nav.notice.no_route':'Aucun itinéraire trouvé : ligne droite affichée.','nav.notice.no_position':'Position actuelle indisponible.',
  'nav.point':'Point désigné','nav.longPress':'Appui long sur la carte : naviguer jusqu’à ce point',
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
  'routes.title':'Routes','routes.refresh':'Refresh','routes.new':'New route','routes.empty':'No route for this event.',
  'routes.points':'points','routes.assigned':'assigned','routes.assignedTo':'Assigned to {name}','routes.addPoints':'Add points',
  'routes.stopAdding':'Finish points','routes.assign':'Assign','routes.unassigned':'Not assigned','routes.computeLegs':'Compute legs',
  'routes.delete':'Delete','routes.deleteConfirm':'Delete the route “{name}”?','routes.readOnly':'Assigned route: only its author and the command post change it.',
  'routes.tapToAdd':'Tap the map to add the points in order.','routes.leg':'Leg','routes.cumulative':'Total','routes.pending':'computation pending',
  'routes.markPassage':'Mark the passage','routes.passageRecorded':'Passage recorded at {name}','routes.report':'Report impracticable',
  'routes.reportReason':'Why is this point impracticable?','routes.reported':'Report sent to the command post','routes.reportFailed':'Report impossible offline',
  'routes.editPoint':'Edit the point','routes.up':'Move up','routes.down':'Move down','routes.deletePoint':'Delete the point',
  'routes.pointType':'Type','routes.legMode':'Leg drawing','routes.radius':'Approach radius: {m} m','routes.comment':'Comment',
  'routes.profile':'Profile','routes.profile.foot':'On foot','routes.profile.vehicle':'Vehicle',
  'routes.leg.straight':'Straight line','routes.leg.paths':'Along paths','routes.gpxSaved':'GPX saved','routes.gpxFailed':'GPX export impossible offline',
  'routes.menu':'Routes and navigation',
  'waypoint.start':'Start','waypoint.pass':'Passage','waypoint.checkpoint':'Checkpoint','waypoint.supply':'Supply','waypoint.finish':'Finish',
  'closures.title':'Closed roads','closures.new':'Close a road','closures.active':'Closed','closures.lifted':'Reopened',
  'closures.lift':'Reopen','closures.restore':'Close again','closures.label':'Name of the closure (e.g. D30 bridge flooded)',
  'closures.drawHelp':'Tap the map to draw the closed road, then Finish.','closures.finish':'Finish','closures.cancel':'Cancel',
  'nav.goHere':'Navigate here','nav.to':'To {label}','nav.computing':'Computing the itinerary…','nav.eta':'arrival {time}',
  'nav.stop':'Stop navigation','nav.arrived':'Arrived','nav.shared':'Itinerary shared with the command post',
  'nav.mode.car':'By car','nav.mode.foot':'On foot','nav.mode.offroad':'Off-road (tracks and paths)',
  'nav.mode.straight':'Straight line','nav.mode.straightHelp':'Distance and bearing, no itinerary',
  'nav.notice.engine_unavailable':'Itinerary computation unavailable: straight line shown.',
  'nav.notice.no_route':'No itinerary found: straight line shown.','nav.notice.no_position':'Current position unavailable.',
  'nav.point':'Designated point','nav.longPress':'Long press on the map: navigate to that point',
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
