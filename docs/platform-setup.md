# Préparation des plateformes

Le dépôt contient le code applicatif commun. Générer les runners Flutter avec :

```
flutter create --platforms=android,ios,web,windows,linux,macos .
flutter pub get
```

## Localisation
Android doit déclarer ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION. iOS doit déclarer NSLocationWhenInUseUsageDescription. Le suivi en arrière-plan sera traité séparément car il exige des permissions et politiques spécifiques.

## Démarrage développement
```
flutter run --dart-define=SARCADE_SERVER_URL=http://ADRESSE_SERVEUR:8000 --dart-define=SARCADE_EVENT_ID=ID_EVENEMENT --dart-define=SARCADE_DEVICE_ID=TERMINAL_01
```

Le style MapLibre de démonstration n'est pas destiné à la production. La stratégie tuiles/styles SARCADE et le téléchargement offline seront définis dans le chantier Offline First.

## iOS
La CI génère le projet iOS (`flutter create --platforms=ios --org org.sarcade`), puis `tool/patch_ios.py` complète `Info.plist` :
- textes d'autorisation pour la localisation, le réseau local et la photothèque
- exception App Transport Security pour le HTTP non chiffré, nécessaire tant que le serveur V0.1 est joint en `http://IP:8000` (à retirer avec le passage en HTTPS)
- nom affiché « SARCADE »

Le job `ios-build` compile sans signature sur un Mac GitHub. La signature et l'envoi vers TestFlight seront ajoutés quand le compte Apple Developer existera : il faudra une clé d'API App Store Connect dans les secrets GitHub, sans Mac local.
