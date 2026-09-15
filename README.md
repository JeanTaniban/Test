# Multiplayer Golf

Jeu de golf multijoueur web en temps réel. Le serveur Node/TypeScript est autoritaire sur la physique, les collisions, le score et l'arrivée dans le trou.

## Installation ordinateur

```bash
npm install
npm run build
npm start
```

Ouvrir `http://localhost:3000`. Une room est créée dans l'URL `/game/XXXXXX`. Ouvrir/copier la même URL dans un second navigateur pour rejoindre la même partie.

En développement :

```bash
npm run dev
```

Vite tourne sur `http://localhost:5173` et proxy le WebSocket vers le serveur `:3000`.

## Jouer sur téléphone

L'interface web fonctionne avec les Pointer Events : souris, stylet et tactile utilisent donc le même protocole de jeu.

Sur téléphone :

1. poser le doigt près de sa balle jaune ;
2. tirer le doigt en arrière ;
3. relâcher pour envoyer le tir.

Le trait jaune montre la direction et la barre en bas du terrain montre la puissance. La zone de prise tactile est volontairement plus grande que la balle affichée. Le terrain bloque le scroll/zoom pendant le geste, tout en conservant le comportement souris sur ordinateur.

Le mode paysage donne plus d'espace au terrain, mais le portrait reste utilisable.

## Héberger depuis Android avec Termux

Utiliser une version actuelle de Termux provenant d'une source officielle (F-Droid ou releases GitHub Termux).

### Première installation

Dans Termux :

```bash
pkg update
pkg install -y git
git clone https://github.com/JeanTaniban/Test.git
cd Test
bash scripts/termux-setup.sh
```

Le script installe les outils nécessaires depuis les dépôts Termux (`nodejs-lts` ou `nodejs`, `git`, `curl`, `cloudflared`), installe les dépendances npm puis compile le client et le serveur.

### Démarrer le serveur + lien Cloudflare

```bash
bash scripts/termux-server.sh start
```

Le gestionnaire :

- démarre le serveur Node sur `127.0.0.1:3000` ;
- vérifie `/health` ;
- démarre un Cloudflare Quick Tunnel ;
- affiche l'URL publique `https://...trycloudflare.com` ;
- conserve les PID et logs dans `.termux-golf/` ;
- demande un wake-lock Termux quand la commande est disponible.

### Commandes Termux

```bash
bash scripts/termux-server.sh status
bash scripts/termux-server.sh url
bash scripts/termux-server.sh logs
bash scripts/termux-server.sh restart
bash scripts/termux-server.sh stop
bash scripts/termux-server.sh update
```

`update` arrête le serveur, effectue un `git pull --ff-only`, réinstalle les dépendances, rebuild puis redémarre.

Pour utiliser un autre port :

```bash
PORT=4000 bash scripts/termux-server.sh start
```

### Android en arrière-plan

Android peut tuer Termux lorsque l'application reste longtemps en arrière-plan. Le script utilise `termux-wake-lock` si disponible, mais il est également conseillé d'autoriser Termux à fonctionner en arrière-plan et de désactiver l'optimisation batterie agressive pour l'application sur le téléphone hôte.

Aucun accès root n'est requis par les scripts.

## Commandes projet

- `npm test` : tests physique, règles, protocole et intégration WebSocket à deux clients ;
- `npm run typecheck` : vérification TypeScript ;
- `npm run build` : client + serveur ;
- `npm start` : serveur de production local.

## Cloudflare Quick Tunnel

Sur ordinateur, après `npm run build && npm start`, dans un second terminal :

```bash
cloudflared tunnel --url http://localhost:3000
```

Cloudflare affiche une URL temporaire `https://...trycloudflare.com`. Ouvrir l'URL, puis utiliser **Copier le lien** pour envoyer la room courante à un ami. Le WebSocket utilise automatiquement `wss://<même-domaine>/ws`.

Les Quick Tunnels sont destinés au test/développement : l'URL change au redémarrage et il n'y a pas de garantie d'uptime.

## Contrôles

### Souris

Clique-glisse depuis la balle : la direction du glissement inversé détermine la direction du tir et sa longueur la puissance.

### Tactile

Pose-glisse-relâche depuis la zone autour de la balle. Une prévisualisation de direction et de puissance est affichée pendant le geste.

On peut tirer pendant que la balle se déplace. Chaque tir accepté par le serveur ajoute un coup.
