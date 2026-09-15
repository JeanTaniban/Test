# Mission 005 — Readiness Cloudflare conforme au fonctionnement de Quick Tunnel

## Contexte

Sur Termux, `cloudflared` passait tous ses pre-checks (DNS, QUIC, HTTP/2, API), obtenait une URL `trycloudflare.com` et journalisait `Registered tunnel connection`. Le script applicatif attendait ensuite qu'un `curl` local vers l'URL publique réponde immédiatement. En cas d'échec temporaire, il envoyait SIGTERM à `cloudflared` et recréait un nouveau Quick Tunnel.

Cette stratégie était incorrecte : elle détruisait un connecteur déjà enregistré et remplaçait inutilement une URL valide.

## Références Cloudflare

Les recommandations Cloudflare pour TryCloudflare sont de lancer un serveur local puis `cloudflared tunnel --url http://localhost:<port>`. Le sous-domaine aléatoire est ensuite routé vers l'origine locale. Cloudflare indique qu'un Quick Tunnel peut prendre un certain temps avant d'être joignable et qu'il est destiné au développement/test.

Cloudflare documente aussi :

- le protocole `auto` comme valeur par défaut, utilisant QUIC puis HTTP/2 en fallback si UDP échoue ;
- les pre-checks automatiques dans `cloudflared` récent ;
- l'incompatibilité de Quick Tunnel avec `~/.cloudflared/config.yml` / `config.yaml` ;
- l'état `Registered` comme connexion du connecteur au réseau Cloudflare.

## Objectifs

1. Ne jamais détruire un Quick Tunnel uniquement parce qu'un probe HTTP public échoue juste après sa création.
2. Utiliser `Registered tunnel connection` comme signal principal de readiness du connecteur.
3. Garder un seul Quick Tunnel tant que `cloudflared` est vivant et enregistré.
4. Laisser `cloudflared` gérer ses propres reconnexions.
5. Conserver le probe `/health` public comme diagnostic non destructif.
6. Refuser explicitement un démarrage Quick Tunnel si un fichier `~/.cloudflared/config.yml` ou `config.yaml` existe.
7. Conserver l'ouverture automatique du navigateur une fois le connecteur enregistré.
8. Enrichir `status` et `doctor` avec l'état du connecteur.

## Critères d'acceptation

- `bash -n scripts/termux-server.sh` passe.
- Les tests, le typecheck, le build et le smoke test serveur restent verts.
- Un log contenant `Registered tunnel connection` produit `Connecteur CF : enregistre`.
- Un probe public temporairement en échec ne provoque aucun `kill` de `cloudflared` et aucune nouvelle URL.
- Un fichier de configuration `.cloudflared/config.yml` ou `.cloudflared/config.yaml` produit une erreur explicite avant le lancement d'un Quick Tunnel.
- `restart` reste la commande explicite pour demander une nouvelle URL.
