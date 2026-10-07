# Flutter / MapLibre

SARCADE App utilise le package Flutter maplibre 0.3.x, choisi pour la cible Android, iOS, Web, Windows, macOS et Linux.

Le client est conçu offline-first. La V0.1 utilise un style de démonstration configurable. La production devra utiliser des styles et tuiles maîtrisés par SARCADE, avec téléchargement offline.

## État V0.1 (octobre 2026)
La carte V0.1 est rendue avec `flutter_map` et des tuiles raster configurables. Le paquet `maplibre` 0.3.6 a été retiré des dépendances : il n'était pas utilisé par le code et son module Android ne compile pas (plugin Gradle `ktlint` manquant dans la version publiée). MapLibre reste la cible pour les styles vectoriels et le offline, à réintégrer avec une version dont le build Android fonctionne.
