# Destinataires et notifications v0.1

## Destinataires
Un message peut viser zéro ou plusieurs identifiants. Convention client V0.1 :
- user:<id>
- team:<id>

Une liste vide signifie diffusion à l'événement. Le serveur conserve les identifiants sans interprétation destructive afin de permettre l'évolution du modèle IAM.

## ACK automatique
À la réception d'un message WebSocket destiné au terminal, le client génère automatiquement un ACK received, le persiste puis le place dans l'Outbox. Les états read, accepted et rejected restent des actions explicites.

## Notifications
NotificationService fournit le point d'abstraction commun : notifications natives sur Android, iOS, Windows, Linux et macOS (flutter_local_notifications), notifications du navigateur pour l'application Web.

### Actions et rappels (décisions du 10 octobre 2026)

| Priorité | Boutons | Son | Rappel |
|---|---|---|---|
| Immédiat | Accepter, Refuser, Ouvrir | **son d'alarme et longue vibration**, canal distinct | **toutes les 2 minutes, 3 fois au plus**, jusqu'à la réponse |
| Urgent | Accepter, Refuser, Ouvrir | prioritaire | non |
| Routine | Lu, Ouvrir | normal | non |

- Accepter, Refuser et Lu donnent l'**accusé de réception** correspondant (`accepted`, `rejected`, `read`), mis dans l'**Outbox** comme une réponse donnée dans l'écran des messages.
- **Application fermée** : Android et iOS traitent l'action dans un isolat d'arrière-plan qui note la réponse dans un fichier et arrête les rappels ; l'application met la réponse dans l'Outbox dès qu'elle tourne (service de premier plan pendant un événement, ou au prochain lancement). Windows et Linux relancent l'application, qui traite l'action au démarrage.
- **Ouvrir** (ou un toucher sur la notification) ouvre l'écran des messages.
- Une réponse, depuis la notification ou l'écran des messages, **arrête les rappels**.
- Rappels programmés par le système sur Android, iOS, macOS et Windows ; sur Linux et sur le Web, tant que l'application est ouverte.
- **Web** : un clic ramène l'application au premier plan sur les messages ; les navigateurs n'offrant pas de boutons fiables sans service worker, la réponse se donne dans l'écran des messages.
- **Android, mode Ne pas déranger** : les messages immédiats peuvent sonner malgré le mode Ne pas déranger **seulement avec le consentement de l'opérateur** (réglage « Messages immédiats même en mode Ne pas déranger »), qui fait demander par Android l'accès « Ne pas déranger » ; canal dédié, réservé aux messages immédiats.
- **iOS** : les messages urgents et immédiats restent en « Time Sensitive » (le niveau critique demande une autorisation d'Apple).
- Manifeste Android complété par `tool/patch_android.py` : récepteurs d'actions et de rappels, redémarrage, vibration, accès Ne pas déranger.
