# Mission 008 — Readiness DNS Quick Tunnel

## Constat

La trace Termux a montré que Node et cloudflared restent actifs et stables alors que le navigateur affiche « site inaccessible ».

Le signal déterminant est :

```text
curl: (6) Could not resolve host: <random>.trycloudflare.com
```

Le `/health` local reste à HTTP 200 et `Registered tunnel connection` est présent. Le problème observé n'est donc pas un crash serveur : le hostname Quick Tunnel n'est pas encore résolu par le DNS du téléphone.

## Objectifs

1. Séparer clairement quatre états : serveur local prêt, connecteur Cloudflare enregistré, DNS public/système prêt, HTTP public prêt.
2. Ne jamais ouvrir Chrome avec un hostname non résolvable.
3. Comparer le résolveur Android/Termux à Cloudflare DNS-over-HTTPS 1.1.1.1.
4. Conserver le même tunnel pendant l'attente ; ne pas recréer une URL.
5. Expliquer explicitement le cas où 1.1.1.1 résout le tunnel mais le DNS Android ne le résout pas.

## Implémentation

- `scripts/termux-dns.sh` centralise les probes DNS et HTTP.
- `system_dns_lookup` utilise `dns.lookup`, donc le chemin de résolution du système.
- Un probe optionnel `curl --doh-url https://1.1.1.1/dns-query` vérifie indépendamment Cloudflare DNS.
- `termux-supervise.sh` attend jusqu'à 120 secondes la résolution système avant d'ouvrir Chrome, puis attend `/health` public.
- `termux-server.sh start` applique la même règle.
- `termux-server.sh status` affiche désormais l'état DNS séparément.
- `termux-server.sh open` refuse d'ouvrir un hostname non résolvable ou un endpoint public non prêt.

## Validation

CI obligatoire :

- syntaxe Bash de tous les scripts Termux ;
- exécution de `system_dns_lookup localhost` ;
- tests du projet ;
- typecheck ;
- build ;
- smoke test serveur.

Le comportement réel `trycloudflare.com` reste à valider sur le téléphone hôte, car il dépend du DNS Android/réseau utilisé.
