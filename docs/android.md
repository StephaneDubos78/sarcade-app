# Android V0.1

## Obtenir l'APK
La CI (`.github/workflows/ci.yml`, job `android-build`) produit un APK à chaque push sur `main`, à chaque pull request, ou à la demande depuis l'onglet Actions (« Run workflow »).

Le fichier est disponible dans l'onglet Actions, sur le run concerné, section Artifacts : `sarcade-android-apk`.

Pour l'installer, copier `app-release.apk` sur le téléphone et autoriser l'installation depuis une source inconnue.

## Premier lancement
Sur téléphone, l'application demande une fois :
- l'adresse du serveur sur le réseau local (par exemple `http://192.168.1.20:8000`, jamais `localhost`)
- l'identifiant de l'événement
- l'identifiant du terminal, unique par opérateur (par exemple `TERRAIN-01`)

Ces valeurs sont conservées sur le téléphone et modifiables dans le menu, rubrique Paramètres. Un seul APK sert donc tous les opérateurs.

Sur Windows, le fonctionnement ne change pas : la configuration vient des `--dart-define` de `tool/run-windows-demo.ps1`, et la rubrique Paramètres permet de la remplacer.

## Génération du runner Android
Le dossier `android/` n'est pas encore versionné. La CI le génère avec `flutter create --platforms=android --org org.sarcade`, puis `tool/patch_android.py` ajoute :
- les permissions Internet, état réseau et localisation au premier plan
- le trafic HTTP/WS non chiffré, nécessaire tant que le serveur V0.1 est joint en `http://` sur le réseau local
- le nom d'application « SARCADE »

## Limites V0.1
- APK signé avec la clé de debug Flutter : installable directement, pas publiable sur le Play Store
- identifiant d'application `org.sarcade.sarcade_app`, à confirmer avant toute publication car il ne pourra plus changer ensuite
- trafic non chiffré autorisé : à retirer quand le serveur sera exposé en HTTPS
- partage de position au premier plan uniquement, le suivi en arrière-plan sera traité séparément
