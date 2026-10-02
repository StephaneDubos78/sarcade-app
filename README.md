# SARCADE App

Client multiplateforme SARCADE pour iOS, Android, Windows, Linux, macOS et Web/PWA lorsque pertinent.

## MVP V0.1
Événements, équipes, cartographie offline, positions GPS temps réel, POI/zones/traces, messages avec ACK, main courante, photos et resynchronisation après perte Internet.

## Technologie cible
Flutter + MapLibre.

## Licence
Mozilla Public License 2.0 (MPL-2.0).


## Windows V0.1 acceptance

The Windows V0.1 client is considered ready for MVP field testing when:
- only one SARCADE client instance can run at a time
- four operators and their latest positions render correctly
- operator history is segmented across temporal gaps
- WebSocket position updates appear without restart
- messages and ACKs are persisted locally
- the Outbox survives loss of server connectivity and can be synchronized manually or automatically
- the logbook is readable
- a Windows release build succeeds in CI

Development launch:
```powershell
.\tool\run-windows-demo.ps1 -EventId "<EVENT_ID>"
```
