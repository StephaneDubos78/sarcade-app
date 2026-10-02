# Offline First — SARCADE App

La V0.1 utilise Hive CE comme stockage local multiplateforme. Il supporte Android, iOS, Linux, macOS, Web et Windows.

## Stockage
- cache positions
- cache POI
- outbox persistante
- curseur de synchronisation par événement

## Principe
Toute donnée terrain est d'abord conservée localement. Une SyncOperation reçoit un identifiant UUID stable. L'outbox est rejouée après reconnexion. Le serveur répond accepted, duplicate, conflict ou rejected.

Le type de connexion réseau n'est jamais considéré comme preuve d'accès au serveur. connectivity_plus sert uniquement de déclencheur de tentative. Toute requête réseau reste protégée par gestion d'erreur.

## Déduplication
Une opération accepted ou duplicate est retirée de l'outbox. Les autres restent disponibles pour traitement/reprise.

## Suite
Ajouter messages/ACK, politique de rétention du cache, chiffrement local, conflits interactifs et tests de coupure réseau prolongée.
