# Messages, ACK et main courante

Les messages et ACK utilisent la même Outbox Offline First que les positions et POI. Un message saisi sans réseau reste local jusqu'à synchronisation.

Priorités : routine, urgent, immediate.

Les ACK applicatifs prévus sont received, read, accepted et rejected. Le serveur alimente une main courante immuable pour les messages et ACK significatifs.

La première UI Messages permet l'émission hors ligne. L'affichage des ACK et de la main courante PCO sera enrichi dans l'itération UX suivante.
