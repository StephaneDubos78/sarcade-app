# ChromeOS / Chromebook

## Canal principal : l'application Android
Les Chromebooks exécutent les applications Android. SARCADE y tourne avec le même APK ou AAB que sur téléphone.

Préparation dans le projet :
- `tool/patch_android.py` déclare l'écran tactile, le GPS et la localisation comme **optionnels**. Sans cela, la permission de localisation rend le GPS obligatoire et le Play Store cache l'application sur les Chromebooks sans GPS ni écran tactile, c'est-à-dire la majorité.
- L'APK contient les bibliothèques `x86_64` (Chromebooks Intel et AMD) et `arm64-v8a` (Chromebooks ARM).
- Sur grand écran, l'interface large (panneaux latéraux, barre complète) s'applique automatiquement, et la fenêtre est redimensionnable.
- Raccourcis clavier façon PowerPoint : Suppr ou Retour arrière (supprimer), Ctrl+Z (annuler), Ctrl+Y ou Ctrl+Maj+Z (rétablir), Ctrl+D (dupliquer), Entrée (terminer un tracé), Échap (annuler le tracé ou désélectionner). Ils sont inactifs pendant la saisie dans un champ texte. Ils servent aussi sous Windows et Linux.
- Sans GPS, le bouton « Partager position » indique que la localisation est indisponible au lieu de planter. Un Chromebook sert donc de poste PCO.

## Installer pour tester
- **Play Store**, piste de test interne : la voie normale dès que le compte Google Play existe.
- **Sans Play Store** : Paramètres → À propos de ChromeOS → Développeurs → activer l'environnement Linux, puis le débogage des applications Android (ADB). Installer ensuite l'APK depuis le terminal Linux avec `adb install sarcade-dev.apk`. Pas besoin du mode développeur ChromeOS.

## Canal secondaire : client Linux
Le job `linux-build` produit `sarcade-linux-x64.tar.gz`, utilisable sur un PC Linux ou dans l'environnement Linux d'un Chromebook x86-64. La localisation n'y est pas garantie. Usage PCO.

## Plus tard : Web / PWA
Une version Web demande d'isoler le code propre aux applications installées (stockage, verrou Windows) et un serveur en HTTPS pour la géolocalisation.
