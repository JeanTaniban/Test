# Mission 002 — Mobile web + hébergement Termux

## Objectif

Rendre Multiplayer Golf réellement jouable depuis un smartphone et permettre d’héberger/gérer le serveur directement depuis Android avec Termux et un Cloudflare Quick Tunnel.

## Périmètre inclus

### Client mobile

- interface responsive téléphone/tablette ;
- contrôles tactiles basés sur Pointer Events ;
- zone de saisie agrandie sur écran tactile ;
- prévisualisation visuelle direction + puissance pendant le drag ;
- annulation propre d’un geste tactile ;
- prévention du scroll/zoom involontaire sur la zone de jeu ;
- prise en compte des safe areas Android/iOS ;
- bouton de copie du lien exploitable sur mobile ;
- indication courte adaptée au tactile ;
- conservation du support souris desktop.

### Termux

- script d’installation des dépendances Termux ;
- installation Node.js LTS, Git, curl et cloudflared via les paquets Termux ;
- build du projet depuis le téléphone ;
- gestion du serveur avec commandes `start`, `stop`, `restart`, `status`, `logs`, `url` ;
- maintien éveillé via `termux-wake-lock` si disponible ;
- lancement en arrière-plan du serveur Node et de `cloudflared` ;
- vérification du endpoint `/health` avant lancement du tunnel ;
- extraction et affichage de l’URL `trycloudflare.com` ;
- stockage des PID et logs dans un dossier local ignoré par Git ;
- documentation de l’installation et des limites Android.

## Hors périmètre

- application Android native ;
- publication Play Store ;
- tunnel Cloudflare nommé/production ;
- service Android natif permanent ;
- garantie de fonctionnement écran éteint malgré les politiques agressives du constructeur ;
- installation automatique de Termux lui-même.

## Fichiers concernés

- `apps/client/src/App.tsx`
- `apps/client/src/style.css`
- `apps/client/index.html`
- `README.md`
- `.gitignore`
- `scripts/termux-setup.sh`
- `scripts/termux-server.sh`
- `.github/workflows/ci.yml` si nécessaire pour valider les scripts

## Contraintes techniques

- le serveur reste autoritaire ; aucune règle de gameplay ne migre côté client ;
- les mêmes messages réseau sont utilisés sur desktop et mobile ;
- aucun framework UI supplémentaire ;
- le tactile ne doit pas casser la souris ;
- les scripts Termux doivent être Bash et ne doivent pas exiger root ;
- `cloudflared` doit être installé depuis le dépôt Termux lorsqu’il est disponible ;
- le Quick Tunnel reste un outil de test/démo, pas un hébergement de production.

## Briques et tests

### Brique A — contrôles mobiles

Test attendu : le code TypeScript compile et les handlers Pointer Events gèrent `down`, `move`, `up`, `cancel` sans modifier le protocole réseau.

### Brique B — responsive

Test attendu : build Vite réussi ; viewport avec `viewport-fit=cover`; CSS sans débordement horizontal volontaire et canvas conservant son ratio.

### Brique C — gestion Termux

Test attendu : `bash -n scripts/termux-setup.sh scripts/termux-server.sh`; validation des commandes et chemins par inspection/CI. Le vrai démarrage Android reste un test manuel matériel.

### Brique D — non-régression

Tests existants physique, règles, protocole et intégration WebSocket toujours verts ; `npm run typecheck` et `npm run build` réussissent.

## Critères de validation

1. le jeu reste jouable à la souris ;
2. un smartphone peut viser et tirer avec un doigt ;
3. la ligne de visée/power apparaît pendant le geste ;
4. la page est utilisable en portrait et paysage ;
5. `scripts/termux-setup.sh` prépare un dépôt cloné dans Termux ;
6. `scripts/termux-server.sh start` démarre le serveur puis le tunnel ;
7. `status`, `url`, `logs`, `restart` et `stop` sont disponibles ;
8. CI : tests, typecheck, build et syntaxe Bash réussis ;
9. la mission est fusionnée uniquement après CI verte.

## Risques

- Android peut tuer Termux en arrière-plan : mitigation par wake-lock + documentation sur l’optimisation batterie ;
- les politiques presse-papiers varient selon navigateur : fallback visuel nécessaire ;
- le doigt masque la balle : zone de capture agrandie et ligne de visée visible ;
- Quick Tunnel temporaire : URL change à chaque redémarrage et aucune garantie d’uptime.
