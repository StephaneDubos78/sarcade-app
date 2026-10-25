# Tests de bout en bout

Spécification : note du coffre « Tests automatiques de bout en bout » (validée le 25 octobre 2026).

- **Serveur réel** : pile de démonstration de `sarcade-server` (PostGIS, services simulés), qui sert le client web de la branche.
- **PCO** : client web piloté par Playwright (arbre d'accessibilité de Flutter).
- **Terminal terrain** : simulé par l'API (`tests/helpers.js`, classe `Terminal`) ; l'émulateur Android le remplacera (étape 2).

## En CI
Job `e2e` de `.github/workflows/ci.yml`, après `web-build`. Branche serveur : `main`, ou celle indiquée par une ligne `server-branch: feat/...` dans la description de la PR. Rapport HTML avec captures en pièce jointe de l'exécution (`e2e-report`).

## En local (Linux, Docker)
```
git clone https://github.com/sdubos-consulting/sarcade-server ../sarcade-server
flutter build web --release --no-web-resources-cdn
export SARCADE_E2E_WEB=$PWD/build/web
docker compose -f ../sarcade-server/demo/docker-compose.demo.yml -f e2e/compose.e2e.yml up -d --build postgres services-stub server
cd e2e && npm install && npx playwright install chromium && npx playwright test
```
