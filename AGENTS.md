# AGENTS.md — sarcade-app

Consignes pour tout assistant de code (Claude, ChatGPT/Codex, autre) qui reprend ce dépôt. À lire avant toute modification.

## Le projet en bref
Application **Flutter** de SARCADE (Android, iPhone, Windows, Linux, web/PWA) pour les bénévoles ADRASEC : carte opérationnelle, positions et stations APRS, messages prioritaires, relevés, main courante, fonctionnement hors ligne (file d'envoi Outbox, Hive). Serveur : `sdubos-consulting/sarcade-server`. État actuel : `SARCADE/00 - Accueil/Reprise du projet par un autre assistant.md` du coffre (seule page d'état à jour ; `99 - Archives` = notes périmées). Spécifications et Kanban : dépôt privé `sdubos-consulting/sarcade-vault` (coffre Obsidian).

## Règles de travail avec le porteur (Stéphane, SDUBOS Consulting)
1. **Aucun développement sans demande explicite.** Une idée nouvelle → proposition avec des **choix par défaut numérotés**, validée avant de coder.
2. Réponses **en français**, style direct.
3. **Aucun secret dans la conversation.** Les secrets restent dans GitHub (signature Android, Google Play, Firebase) et ne sont lus que par la CI.
4. Commandes pour le porteur : **un bloc copiable par machine**, avec le **résultat attendu**.
5. Une branche et une PR par sujet ; **fusion après accord du porteur et CI verte**. Éviter de fusionner deux PR à quelques secondes d'intervalle.
   **Une fusion n'est pas une recette** : après fusion, la carte du Kanban va en « À recetter » ; elle ne passe en « Validé » que sur confirmation du porteur.
6. Commits signés `SDUBOS Consulting <github@sdubos.com>`.
7. Mettre le coffre à jour (note, Kanban, fiche de test) après chaque étape.

## Construire et tester
- Les dossiers `android/`, `ios/`, `web/`, `windows/`, `linux/` **ne sont pas dans le dépôt** : la CI les génère (`flutter create --org org.sarcade`) puis les adapte avec `tool/patch_*.py`.
- Localement : `flutter analyze` (aucune remarque tolérée, même « info ») puis `flutter test`.
- CI (`.github/workflows/ci.yml`) : analyse et tests, builds des cinq plateformes, test de bout en bout web (Playwright, `e2e/`) et Android (émulateur, `integration_test/`).
- Si le SDK Flutter n'est pas disponible dans l'environnement de l'assistant, s'appuyer sur la CI et lire les annotations des jobs.

## Distribution
- Android : chaque fusion dans `main` produit un APK (pré-release `android-dev`) et un AAB **envoyé en brouillon sur la piste Test interne de Google Play** ; le porteur clique « Publier ». Identifiant `org.sarcade.sarcade_app`, `versionCode` = numéro de run CI.
- Web : archive `web-dev`, servie par le serveur du NAS ; le code est nommé `main.<build>.dart.js` (`tool/version_web.py`) pour éviter les versions bloquées en cache.
- Réveil application fermée : Firebase (Android) et Web Push, voir `sarcade-server/docs/wakeup-v0.1.md`.

## Travail à plusieurs assistants (Claude et ChatGPT en parallèle)
Décision du porteur, 28 octobre 2026, 23 h 10.
1. **Un sujet = un assistant.** Prendre une carte la passe en « En cours » du Kanban avec l'étiquette `#claude` ou `#chatgpt` ; une carte étiquetée par l'autre ne se touche pas. Le porteur attribue les cartes.
2. **Branches préfixées** `claude/…` ou `chatgpt/…`, une PR par sujet, branche remise à jour depuis `main` avant la PR et après chaque fusion.
3. **Zones séparées** autant que possible (par dépôt ou par écran) ; `lib/src/features/map/operational_map_page.dart` est le fichier le plus exposé aux conflits : y faire des modifications courtes, ou extraire d'abord le code concerné dans un fichier à part.
4. **Ressources numérotées réservées** sur la carte avant écriture : numéro de migration Alembic, ajout de dépendance (`uv.lock`, `pubspec.lock`) — un seul à la fois.
5. **Fusion par le porteur seul**, une PR à la fois, CI verte.
6. **Coffre partagé** : `git pull` juste avant d'écrire, petit commit juste après ; section « Qui fait quoi » dans la note de reprise.

## Pièges connus
- Test Android « urgent message notification not shown » instable : relancer le job avant de chercher un bug.
- `lib/src/features/map/operational_map_page.dart` est gros et souvent en conflit : fusionner `main` dans la branche avant la PR.
- Textes : `lib/src/l10n/strings.dart`, toujours en français **et** en anglais.
- Les fonctions du web passent par `lib/src/platform/platform_services_web.dart` (équivalent `_io` pour les autres plateformes).

## Accès dont l'assistant a besoin
- GitHub sur `sarcade-app`, `sarcade-server`, `sarcade-vault` : Contents, Pull requests, Actions en lecture/écriture ; Checks en lecture.
- Un environnement avec git (et si possible le SDK Flutter stable) ; réseau vers GitHub et pub.dev.
- Play Console, Firebase, Cloudflare, NAS : actions faites par le porteur.
