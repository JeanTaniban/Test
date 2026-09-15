# Mission 006 — Diagnostic Termux des arrêts serveur

## Contexte

Le serveur et le Quick Tunnel peuvent sembler démarrer correctement puis devenir inaccessibles après le passage de Termux au navigateur Android. Les logs précédents ne permettent pas de déterminer avec certitude si Node plante, si `cloudflared` s'arrête, si Android tue un processus, ou si seul le chemin réseau public échoue.

## Objectif

Produire suffisamment de télémétrie locale pour diagnostiquer un arrêt à partir d'un seul rapport copiable.

## Livrables

- instrumentation du cycle de vie Node : PID, version, plateforme, cwd, signaux, erreurs fatales et code de sortie ;
- heartbeat Node toutes les 30 secondes avec mémoire RSS/heap ;
- watchdog Termux indépendant qui surveille Node, `cloudflared` et `/health` local ;
- journalisation des transitions de processus et de l'ouverture du navigateur ;
- commande `doctor` générant un rapport horodaté dans `.termux-golf/` ;
- état `/proc` des processus, RSS, threads et OOM scores ;
- résolution DNS de l'URL `trycloudflare.com` ;
- probes HTTP public standard, HTTP/1.1 et IPv4 ;
- versions Node/npm/cloudflared/curl et informations Android/Termux disponibles ;
- tails de `server.log`, `tunnel.log` et `watchdog.log` ;
- validation syntaxique Bash en CI.

## Critères de validation

- `bash -n` passe pour tous les scripts Termux ;
- tests, typecheck, build et smoke test serveur restent verts ;
- `start` démarre le watchdog sans changer l'autorité du serveur ni le protocole jeu ;
- `stop` arrête proprement le watchdog, le tunnel et Node ;
- `doctor` reste non destructif et n'affiche pas de variables d'environnement sensibles.
