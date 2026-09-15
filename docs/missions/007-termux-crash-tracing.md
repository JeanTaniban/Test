# Mission 007 — Tracer précisément les crashs Termux

## Problème

Le démarrage Termux peut annoncer Node et le Quick Tunnel comme prêts, puis Chrome affiche immédiatement un site inaccessible. Les diagnostics précédents constataient surtout l'état après coup et ne permettaient pas de savoir si le navigateur avait réellement atteint Node ni quel code de sortie avait terminé Node/cloudflared.

## Objectifs

- journaliser chaque requête HTTP entrante côté Node (méthode, URL, host, user-agent, statut, durée) ;
- journaliser les upgrades et connexions WebSocket ;
- capturer les erreurs HTTP/WebSocket ;
- exécuter Node et cloudflared sous un superviseur foreground pendant les 60 premières secondes ;
- capturer le code de sortie réel de chaque enfant ;
- afficher les logs Node/cloudflared en direct pendant la reproduction ;
- afficher toutes les 5 s l'état `/proc`, RSS, threads, OOM score et les healthchecks local/public ;
- ouvrir Chrome depuis ce superviseur afin que la transition Termux → Chrome soit incluse dans la trace ;
- intégrer `supervisor.log` au rapport `doctor`.

## Commande de reproduction

```bash
bash scripts/termux-debug.sh
```

Le script rebuild, arrête les anciens processus, démarre Node et cloudflared sous `termux-supervise.sh`, ouvre Chrome, puis observe pendant 60 secondes.

Si Chrome affiche une erreur, revenir immédiatement dans Termux sans redémarrer. La trace doit permettre de voir :

- aucune requête navigateur reçue : problème avant l'origine (DNS/TLS/Cloudflare/Android) ;
- requêtes HTTP reçues mais pas de WebSocket : problème client/protocole ;
- `FATAL node exited rc=137` ou processus disparu : kill externe probable ;
- autre code de sortie Node : erreur applicative à analyser dans `server.log` ;
- sortie cloudflared : tunnel interrompu ;
- Node et cloudflared vivants + health local OK mais public KO : problème de chemin Cloudflare/réseau.

## Validation CI

- syntaxe Bash des scripts setup/server/watchdog/diagnose/debug/supervise ;
- tests existants ;
- typecheck TypeScript ;
- build client/serveur ;
- smoke test `/health` de l'artefact serveur.
