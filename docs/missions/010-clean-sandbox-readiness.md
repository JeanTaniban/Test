# Mission 010 — nettoyer la readiness Termux

## Objectif

Supprimer des scripts de lancement les derniers concepts et libellés hérités qui faisaient référence au DNS système Termux alors que la readiness est désormais indépendante de ce résolveur.

## Changements

- `termux-server.sh` est simplifié et reconstruit autour de trois signaux : `/health` local, `Registered tunnel connection`, puis readiness publique Cloudflare.
- La readiness publique utilise uniquement `cloudflare_doh_lookup_a` et `public_health_via_ip`.
- `status` affiche explicitement `Resolver Termux : non utilise pour la readiness`.
- `open` valide la route publique avec DoH + `curl --resolve` avant de lancer Android/Chrome.
- `termux-supervise.sh` n'emploie plus `system_dns_lookup` et ne journalise plus de faux état `system DNS READY`.
- Les heartbeats debug indiquent l'IP Cloudflare utilisée pour la route publique et `local_dns=unused`.

## Contraintes

Aucun `ping`, `ip`, netlink, socket raw, interface réseau ou DNS système Termux n'est nécessaire pour décider si le tunnel est prêt.

## Validation

- syntaxe Bash de tous les scripts ;
- test déterministe du parseur DoH ;
- tests projet ;
- typecheck ;
- build ;
- smoke test du serveur compilé.
