# ChromeOS / Chromebook

## Canal principal : l'application Web installable (PWA)
Sur ChromeOS, l'application native est une application Web installable. SARCADE s'installe depuis Chrome (icône d'installation dans la barre d'adresse) et devient une application ChromeOS à part entière :
- sa propre fenêtre, sans barre de navigateur, redimensionnable, en écran partagé et en tablette
- une icône dans l'étagère et le lanceur
- clavier et souris : raccourcis façon PowerPoint sur la carte (Suppr, Ctrl+Z, Ctrl+Y, Ctrl+D, Entrée, Échap), molette pour zoomer
- fonctionne sur les Chromebooks gérés (écoles, collectivités) où le Play Store et Linux sont souvent désactivés, et se déploie par la console d'administration Google

### Architecture
- **Le serveur SARCADE sert lui-même l'application Web.** Elle s'ouvre à l'adresse du serveur (`https://serveur-sarcade/`), au même endroit que l'API : pas de CORS, et fonctionnement sur le réseau local sans Internet.
- Le moteur de rendu est embarqué (`--no-web-resources-cdn`) au lieu d'être téléchargé chez Google au démarrage.
- Les données locales (Outbox, objets, cache) sont dans la base IndexedDB du navigateur, conservée hors connexion.
- Les fichiers ouverts et les exports GeoJSON deviennent des téléchargements du navigateur.
- Le code propre aux applications installées (stockage Windows, verrou mono-instance, fichiers) est isolé dans `lib/src/platform/` (`platform_services_io.dart` pour les applications installées, `platform_services_web.dart` pour le navigateur). Tout le reste est commun.

### Prérequis : HTTPS
Chrome n'autorise la géolocalisation et l'installation d'une PWA que sur une page sécurisée (HTTPS). Le serveur V0.1 est en HTTP : l'application Web s'ouvre, mais elle ne pourra être installée et partager la position qu'après le passage du serveur en HTTPS.

### Étapes suivantes
1. Serveur en HTTPS, y compris sur un réseau local sans Internet (certificat d'un domaine `sarcade.org` ou autorité locale déployée sur les appareils).
2. Service worker SARCADE pour démarrer l'application sans réseau (le service worker généré par Flutter est déclaré obsolète) et polices embarquées.
3. Ouverture directe des fichiers GPX, KML et GeoJSON depuis l'application Fichiers de ChromeOS (`file_handlers` du manifeste).

## Canal de repli : l'application Android
L'application Android reste installable sur Chromebook depuis le Play Store, avec les fonctions matérielles déclarées optionnelles (écran tactile, GPS) pour ne pas être masquée. Elle sert de solution transitoire tant que le serveur n'est pas en HTTPS.

Installation de test sans Play Store : environnement Linux et débogage des applications Android dans les paramètres développeurs, puis `adb install sarcade-dev.apk`.

## Client Linux
Le job `linux-build` produit `sarcade-linux-x64.tar.gz`, utilisable sur un PC Linux ou dans l'environnement Linux d'un Chromebook x86-64.
