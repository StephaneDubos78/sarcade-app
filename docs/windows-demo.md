# SARCADE App — première démonstration Windows

## Objectif
Afficher sur la carte SARCADE les opérateurs fournis par SARCADE Server.

## Prérequis
Le Server Docker doit répondre sur http://localhost:8000/health.

Pour compiler une application Flutter Windows, Flutter SDK et la chaîne C++ Visual Studio sont nécessaires. Le script tool/install-flutter-windows.ps1 prépare Git et Visual Studio Build Tools. Flutter stable doit être installé dans C:\dev\flutter puis ajouté au PATH.

## Vérification
```powershell
flutter config --enable-windows-desktop
flutter doctor -v
```

## Lancement
Depuis le repository sarcade-app :
```powershell
.\tool\run-windows-demo.ps1 -EventId "ID-EVENEMENT"
```

Exemple avec le test du 2 octobre 2026 :
```powershell
.\tool\run-windows-demo.ps1 -EventId "dd8b6cdf-b18a-4ff4-8128-0b70f37046e7"
```

Le client utilise localhost:8000 et l'identité de démonstration pco-windows par défaut.

## ARM64
Le PC de recette actuel est Windows ARM64. La disponibilité de la cible native Windows ARM64 dépend de la chaîne Flutter/Visual Studio installée. Si Flutter ne propose pas une cible Windows utilisable, la solution de repli du MVP sera le client Web Flutter dans Edge, qui reste connecté au même SARCADE Server.
