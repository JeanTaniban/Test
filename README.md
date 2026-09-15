# Multiplayer Golf

Jeu de golf multijoueur web en temps réel. Le serveur Node/TypeScript est autoritaire sur la physique, les collisions, le score et l'arrivée dans le trou.

## Installation

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

## Commandes

- `npm test` : tests physique, règles, protocole et intégration WebSocket à deux clients ;
- `npm run typecheck` : vérification TypeScript ;
- `npm run build` : client + serveur ;
- `npm start` : serveur de production local.

## Cloudflare Quick Tunnel

Après `npm run build && npm start`, dans un second terminal :

```bash
cloudflared tunnel --url http://localhost:3000
```

Cloudflare affiche une URL temporaire `https://...trycloudflare.com`. Ouvrir l'URL, puis utiliser **Copier le lien** pour envoyer la room courante à un ami. Le WebSocket utilise automatiquement `wss://<même-domaine>/ws`.

## Contrôles

Clique-glisse depuis votre balle : la direction du glissement inversé détermine la direction du tir et sa longueur la puissance. On peut tirer pendant que la balle se déplace. Chaque tir accepté par le serveur ajoute un coup.
