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

Le script installe les outils nécessaires depuis les dépôts Termux (`nodejs-lts` ou `nodejs`, `git`, `curl`, `cloudflared`), installe les dépendances npm, compile le client, compile le serveur avec TypeScript puis exécute un smoke test `/health` sur l'artefact serveur réellement produit.

Le serveur n'utilise pas le CLI `esbuild` pour son build de production. Cette décision évite les incompatibilités du binaire natif esbuild observées sur Android/Termux. Vite reste utilisé pour compiler le client web.

### Démarrer le serveur + lien Cloudflare

```bash
bash scripts/termux-server.sh start
```

Le gestionnaire :

- démarre directement le processus Node sur `127.0.0.1:3000` et conserve son vrai PID ;
- vérifie le `/health` local ;
- démarre un seul Cloudflare Quick Tunnel ;
- attend que Cloudflare attribue l'URL `trycloudflare.com` ;
- attend le log `Registered tunnel connection`, qui confirme que le connecteur `cloudflared` est attaché au réseau Cloudflare ;
- conserve ce tunnel tant que le processus et le connecteur restent actifs ;
- effectue ensuite un probe HTTP public uniquement comme diagnostic non destructif ;
- ouvre l'URL dans Chrome si Chrome est disponible, sinon via le gestionnaire d'URL Android ;
- conserve les PID et logs dans `.termux-golf/` ;
- demande un wake-lock Termux quand la commande est disponible.

Le script ne détruit plus un tunnel correctement enregistré simplement parce qu'un `curl` vers l'URL publique ne répond pas immédiatement. Un Quick Tunnel peut prendre un court délai avant d'être joignable publiquement, et `cloudflared` gère lui-même les reconnexions du connecteur.

Cloudflare indique également que Quick Tunnels ne sont pas compatibles avec un fichier `~/.cloudflared/config.yml` ou `~/.cloudflared/config.yaml`. Le script vérifie ce cas avant le démarrage et affiche une erreur explicite au lieu de lancer une configuration ambiguë.

Pour désactiver l'ouverture automatique :

```bash
AUTO_OPEN_BROWSER=0 bash scripts/termux-server.sh start
```

### Commandes Termux

```bash
bash scripts/termux-server.sh status
bash scripts/termux-server.sh doctor
bash scripts/termux-server.sh url
bash scripts/termux-server.sh open
bash scripts/termux-server.sh logs
bash scripts/termux-server.sh restart
bash scripts/termux-server.sh stop
bash scripts/termux-server.sh update
```

`status` vérifie séparément le processus Node, le processus `cloudflared`, l'enregistrement du connecteur, le `/health` local et le probe public. `doctor` ajoute la version de `cloudflared`, la détection d'un éventuel fichier de configuration incompatible et les dernières lignes des deux logs. `open` exige un connecteur Cloudflare enregistré, mais ne bloque pas uniquement sur un probe HTTP local. `update` arrête le serveur, effectue un `git pull --ff-only`, réinstalle les dépendances, rebuild puis redémarre.

Pour utiliser un autre port :

```bash
PORT=4000 bash scripts/termux-server.sh start
```

### Mettre à jour une installation existante

Depuis le dossier `Test` :

```bash
git pull --ff-only
bash scripts/termux-server.sh restart
```

Si les dépendances ou le build ont changé, utiliser plutôt :

```bash
bash scripts/termux-server.sh update
```

Il n'est pas nécessaire de supprimer ou recloner le dépôt.

### Diagnostic

Si le navigateur indique que le site est inaccessible :

```bash
bash scripts/termux-server.sh doctor
```

Un état sain ressemble à :

```text
Node          : actif (...)
cloudflared   : actif (...)
Connecteur CF : enregistre
Health local  : OK
URL           : https://....trycloudflare.com
Health public : OK
```

`Connecteur CF : enregistre` est le signal principal côté tunnel. Si ce statut est bon mais que `Health public` indique encore `en propagation / probe local en echec`, le script conserve le même tunnel : attendre quelques secondes puis recharger la page est préférable à recréer une nouvelle URL.

### Android en arrière-plan

Android peut tuer Termux lorsque l'application reste longtemps en arrière-plan. Le script utilise `termux-wake-lock` si disponible, mais il est également conseillé d'autoriser Termux à fonctionner en arrière-plan et de désactiver l'optimisation batterie agressive pour l'application sur le téléphone hôte.

Aucun accès root n'est requis par les scripts.

## Commandes projet

- `npm test` : tests physique, règles, protocole et intégration WebSocket à deux clients ;
- `npm run typecheck` : vérification TypeScript ;
- `npm run build` : client + serveur ;
- `npm run smoke:server` : démarre l'artefact compilé et valide `/health` ;
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
