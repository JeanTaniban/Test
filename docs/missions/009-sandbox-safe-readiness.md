# Mission 009 — readiness compatible sandbox Termux

## Constat

Le mode debug de la mission 007 a montré que Node et `cloudflared` restent vivants, avec `/health` local à 200, tandis qu'un lookup du hostname `*.trycloudflare.com` depuis Termux peut échouer.

Ce lookup ne doit pas être utilisé comme vérité sur le DNS de Chrome/Android : Termux tourne dans une sandbox Android et différents runtimes/outils peuvent avoir un comportement de résolution différent.

## Objectif

Valider la publication et la route publique d'un Quick Tunnel sans dépendre du résolveur DNS local de Termux.

## Stratégie

1. attendre `Registered tunnel connection` dans `cloudflared` ;
2. interroger Cloudflare DNS over HTTPS sur `cloudflare-dns.com` en forçant la connexion TCP/TLS vers `1.1.1.1` (fallback `1.0.0.1`) avec `curl --resolve` ;
3. extraire les enregistrements A du hostname Quick Tunnel ;
4. tester `https://<quick-tunnel>/health` avec `curl --resolve <hostname>:443:<ip>`, ce qui conserve SNI et Host tout en évitant tout lookup DNS local ;
5. ouvrir Chrome uniquement lorsque cette route publique répond ;
6. ne jamais utiliser `ping`, `ip`, netlink ou une interface réseau privilégiée pour la readiness.

## Contraintes

- connexions HTTPS sortantes ordinaires uniquement ;
- aucun root ;
- aucun accès à une interface réseau Android ;
- pas de dépendance au DNS système Termux ;
- conserver le même Quick Tunnel pendant l'attente ;
- le navigateur reste responsable de sa propre résolution DNS Android.

## Compatibilité

Les anciens noms de fonctions de la mission 008 sont temporairement conservés comme shims pour éviter une régression des scripts existants, mais ils sont redirigés vers la readiness DoH/IP forcée et n'interrogent plus le résolveur local.

## Validation

- `bash -n` sur tous les scripts Termux ;
- test déterministe du parseur JSON DoH ;
- suite de tests projet ;
- typecheck ;
- build client/serveur ;
- smoke test `/health` du serveur compilé.
