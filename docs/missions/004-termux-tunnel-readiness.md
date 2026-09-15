# Mission 004 — Fiabiliser le runtime Termux et le Quick Tunnel

## Contexte

Sur Android/Termux, le build et le smoke test serveur réussissent, mais le navigateur peut être ouvert alors que Cloudflare a seulement attribué une URL sans que le tunnel soit encore réellement joignable. Le script suivait également le PID du processus `npm start` au lieu du processus Node de production lui-même.

## Objectifs

- ne considérer le serveur prêt qu'après validation du `/health` local et du `/health` public Cloudflare ;
- ne jamais ouvrir automatiquement Chrome avant que le Quick Tunnel soit joignable ;
- relancer automatiquement le Quick Tunnel en cas d'échec transitoire ;
- suivre directement le PID du processus Node ;
- améliorer le diagnostic utilisateur sans devoir lire manuellement les fichiers de logs.

## Modifications

### Runtime Node

Le gestionnaire Termux lance directement :

```bash
node dist/server/apps/server/src/index.js
```

Le PID enregistré dans `.termux-golf/server.pid` correspond donc au processus Node réel.

### Validation Cloudflare

Après détection de l'URL `trycloudflare.com`, le script interroge :

```text
https://<tunnel>.trycloudflare.com/health
```

Le démarrage n'est déclaré réussi que si la réponse contient `{"ok":true}`.

Le script effectue jusqu'à trois tentatives complètes de Quick Tunnel si l'URL n'est pas attribuée, si `cloudflared` se termine ou si le `/health` public ne devient pas disponible.

### Navigateur

Chrome / le navigateur Android n'est ouvert qu'après validation du `/health` public. La commande `open` effectue la même validation avant d'ouvrir l'URL.

### Diagnostic

`status` affiche séparément :

- PID Node ;
- PID cloudflared ;
- healthcheck local ;
- URL publique ;
- healthcheck public.

`doctor` ajoute les dernières lignes de `server.log` et `tunnel.log` et indique la disponibilité de `termux-wake-lock`.

## Critères de validation

- syntaxe Bash valide ;
- tests existants inchangés et verts ;
- typecheck vert ;
- build client/serveur vert ;
- smoke test serveur compilé vert ;
- le script ne peut plus annoncer `Serveur pret` avant un `/health` public réussi ;
- l'ouverture automatique se produit uniquement après validation du tunnel ;
- les PID suivis correspondent directement à Node et cloudflared.

## Limites

La CI ne peut pas créer un véritable Quick Tunnel depuis GitHub Actions pour ce scénario Android. La validation réelle du tunnel reste donc à reproduire sur Termux. Android peut aussi imposer des restrictions d'arrière-plan indépendantes du script ; le wake-lock réduit le risque de suspension CPU mais ne remplace pas les réglages d'optimisation batterie du téléphone hôte.
