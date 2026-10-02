# Destinataires et notifications v0.1

## Destinataires
Un message peut viser zéro ou plusieurs identifiants. Convention client V0.1 :
- user:<id>
- team:<id>

Une liste vide signifie diffusion à l'événement. Le serveur conserve les identifiants sans interprétation destructive afin de permettre l'évolution du modèle IAM.

## ACK automatique
À la réception d'un message WebSocket destiné au terminal, le client génère automatiquement un ACK received, le persiste puis le place dans l'Outbox. Les états read, accepted et rejected restent des actions explicites.

## Notifications
NotificationService fournit le point d'abstraction commun. La V0.1 actuelle utilise un fallback portable. Les notifications natives Android/iOS seront activées lorsque les runners de plateforme et leurs permissions seront versionnés.
