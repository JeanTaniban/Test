# Cahier des charges — Multiplayer Golf

**Projet :** Multiplayer Golf  
**Dépôt :** `JeanTaniban/Test`  
**Statut :** CDC global initial  
**Version :** 0.1

## 1. Objectif

Développer un jeu de golf multijoueur web en vue de dessus, jouable directement depuis un navigateur.

Un joueur héberge localement le jeu et obtient une URL publique temporaire via Cloudflare Quick Tunnel. Il peut copier cette URL et l'envoyer à un ami. L'ouverture du lien doit permettre de rejoindre directement la partie, sans installation ni configuration réseau côté invité.

La particularité du gameplay est que les joueurs ne jouent pas chacun leur tour : chacun peut tirer dès qu'il le souhaite, y compris pendant que sa balle est encore en mouvement. Les balles peuvent entrer en collision entre elles. Le classement est déterminé principalement par le nombre de coups nécessaires pour atteindre le trou.

## 2. Périmètre fonctionnel

### 2.1 Inclus dans la première version jouable

- application web React + TypeScript ;
- serveur Node.js + TypeScript ;
- communication temps réel par WebSocket ;
- création/rejoindre une partie par URL ;
- exposition locale par Cloudflare Quick Tunnel ;
- bouton de copie du lien de partie ;
- au moins 2 joueurs simultanés ;
- terrain 2D vu du dessus ;
- une balle par joueur ;
- visée et puissance de tir ;
- possibilité de tirer sans attendre son tour ;
- possibilité de tirer pendant que la balle est en mouvement ;
- collisions balle/balle ;
- collisions balle/décor ;
- friction et ralentissement ;
- détection du trou ;
- comptage serveur du nombre de coups ;
- état de fin de joueur ;
- classement par nombre de coups ;
- synchronisation client/serveur ;
- reconnexion courte d'un joueur après rafraîchissement ou coupure réseau.

### 2.2 Hors périmètre initial

- comptes utilisateurs ;
- base de données persistante ;
- matchmaking public ;
- anti-triche avancé ;
- serveur dédié de production ;
- classement global persistant ;
- éditeur de niveaux ;
- chat vocal ;
- application mobile native ;
- moteur physique généraliste complexe.

Ces éléments pourront être ajoutés après validation du socle multijoueur.

## 3. Technologies

### Client

- React ;
- TypeScript ;
- Vite ;
- Canvas 2D pour le rendu du jeu ;
- WebSocket navigateur natif.

### Serveur

- Node.js ;
- TypeScript ;
- bibliothèque `ws` pour WebSocket ;
- boucle de simulation serveur fixe.

### Partagé

Un package TypeScript partagé entre client et serveur contiendra :

- les types réseau ;
- les types de jeu ;
- les constantes partagées ;
- la version du protocole.

### Exposition réseau

Le serveur local sera exposé par Cloudflare Quick Tunnel, par exemple :

```bash
cloudflared tunnel --url http://localhost:3000
```

Le même endpoint public doit transporter la page HTTP(S) et les WebSockets afin d'éviter une architecture multi-origine inutile.

## 4. Architecture cible

```text
Internet
   |
Cloudflare Quick Tunnel
   |
HTTPS / WSS
   |
Node.js / TypeScript
   |-- HTTP : application React compilée
   |-- WebSocket : protocole temps réel
   |-- RoomManager
   |-- GameRoom
   |-- PhysicsWorld
   |-- Score / règles
   |
Clients React + Canvas
```

Le serveur constitue l'autorité de référence pour l'état de la partie.

## 5. Autorités client / serveur

### 5.1 Autorité serveur

Le serveur est seul autoritaire sur :

- position réelle des balles ;
- vitesse réelle des balles ;
- application des impulsions de tir ;
- validation d'un tir ;
- collisions balle/balle ;
- collisions avec les obstacles ;
- friction ;
- détection de l'entrée dans le trou ;
- compteur de coups ;
- état terminé/non terminé ;
- ordre et résultats de la manche ;
- présence et identité réseau des joueurs ;
- règles de la room.

Un client ne peut jamais imposer directement une position, une vitesse, un score ou un état de victoire.

### 5.2 Responsabilités client

Le client est responsable de :

- capture souris/tactile ;
- calcul de l'intention de tir ;
- caméra ;
- rendu ;
- interface ;
- sons et effets ;
- interpolation des joueurs distants ;
- éventuelle prédiction locale du joueur ;
- affichage d'une trajectoire indicative non autoritaire.

Le client envoie des intentions, par exemple :

```ts
type ShootMessage = {
  type: "shoot";
  sequence: number;
  angle: number;
  power: number;
};
```

## 6. Modèle de synchronisation

### 6.1 Simulation

Valeurs initiales retenues :

- simulation physique serveur : **60 Hz** ;
- diffusion de snapshots : **20 Hz** ;
- rendu client : cadence de l'écran.

La simulation doit utiliser un pas fixe afin de limiter les différences liées au temps d'exécution.

### 6.2 Snapshots

Le serveur transmet périodiquement un état contenant au minimum :

```ts
type Snapshot = {
  tick: number;
  serverTime: number;
  players: Array<{
    id: string;
    x: number;
    y: number;
    vx: number;
    vy: number;
    shots: number;
    finished: boolean;
  }>;
};
```

Les joueurs distants sont affichés par interpolation entre plusieurs snapshots afin d'éviter les mouvements saccadés.

### 6.3 Prédiction locale

Une prédiction locale pourra être utilisée pour la balle du joueur afin que le tir paraisse instantané.

La prédiction n'est jamais autoritaire. Lorsqu'un snapshot serveur diffère de l'état prédit :

- petite erreur : correction progressive ;
- erreur importante : resynchronisation immédiate.

La V1 peut fonctionner d'abord sans prédiction si la synchronisation autoritaire est validée, puis l'ajouter comme optimisation de latence.

## 7. Gameplay

### 7.1 Tir

Le joueur choisit :

- une direction ;
- une puissance comprise dans des limites serveur.

Chaque tir accepté :

- applique une impulsion à la balle ;
- incrémente le compteur de coups de 1.

Le joueur peut tirer alors que sa balle est déjà en mouvement.

Le serveur doit rejeter :

- puissance hors limites ;
- données non numériques/non finies ;
- séquence déjà traitée ;
- tir d'un joueur terminé ;
- message invalide ou incompatible avec le protocole.

### 7.2 Collisions

Le moteur doit au minimum gérer :

- cercle contre cercle ;
- cercle contre segment ou paroi ;
- résolution de pénétration ;
- impulsion/rebond ;
- restitution configurable ;
- friction/amortissement.

Les collisions entre balles permettent volontairement de pousser ou dévier un adversaire.

### 7.3 Trou

L'entrée dans le trou est décidée par le serveur.

Une simple intersection géométrique ne doit pas nécessairement suffire : une vitesse maximale d'entrée pourra être imposée pour éviter qu'une balle très rapide traversant le trou soit comptée comme rentrée.

Une fois terminée, la balle :

- est marquée `finished` ;
- n'accepte plus de tirs ;
- ne doit plus perturber les autres balles ;
- peut jouer une animation de disparition uniquement côté client.

### 7.4 Classement

Le critère principal est le nombre de coups croissant.

Le temps d'arrivée n'est pas le critère principal. Deux joueurs ayant le même nombre de coups sont ex æquo tant qu'aucune règle supplémentaire n'est explicitement définie.

## 8. Rooms et URL de partie

Une partie possède un identifiant court non prédictible, par exemple :

```text
https://xxxxx.trycloudflare.com/game/H7KD2M
```

À l'ouverture :

1. React extrait le `roomId` de l'URL ;
2. le client ouvre le WebSocket sur le même domaine ;
3. le client envoie un message `join` ;
4. le serveur valide la room et affecte/reconnecte le joueur ;
5. l'état courant est envoyé au nouveau joueur.

Même si une seule room est nécessaire au début, le code serveur doit isoler l'état dans une abstraction `GameRoom` afin de permettre plusieurs parties ultérieurement.

## 9. Identité et reconnexion

Le client conserve un token joueur aléatoire dans le stockage local du navigateur.

Exemple conceptuel :

```ts
crypto.randomUUID();
```

À la reconnexion, ce token permet au serveur de rattacher temporairement le navigateur à la même balle.

Une période de grâce initiale de l'ordre de 15 secondes pourra être utilisée avant suppression définitive d'un joueur déconnecté.

Aucune donnée de confiance ne doit être déduite uniquement du stockage client.

## 10. Protocole réseau

Le protocole doit être explicitement typé et versionné.

Messages client initiaux envisagés :

- `join` ;
- `shoot` ;
- `ping`.

Messages serveur initiaux envisagés :

- `welcome` ;
- `snapshot` ;
- `playerJoined` ;
- `playerLeft` ;
- `gameStateChanged` ;
- `gameOver` ;
- `pong` ;
- `error`.

Le serveur doit valider toutes les données reçues avant de les utiliser.

## 11. États de partie

La room doit utiliser un automate explicite :

```text
WAITING -> PLAYING -> FINISHING -> RESULTS
                 ^                    |
                 +--------------------+
```

### WAITING

Attente des joueurs et préparation.

### PLAYING

Simulation active et tirs autorisés.

### FINISHING

État optionnel permettant de laisser finir les joueurs restants ou d'appliquer un délai maximal.

### RESULTS

Affichage des résultats et possibilité de relancer une manche.

La première V1 technique peut temporairement démarrer directement en `PLAYING` si l'automate complet n'est pas encore nécessaire au test réseau.

## 12. Structure cible du dépôt

```text
/
├── CDC.md
├── README.md
├── package.json
├── apps/
│   ├── client/
│   │   └── src/
│   │       ├── game/
│   │       ├── network/
│   │       └── ui/
│   └── server/
│       └── src/
│           ├── game/
│           ├── network/
│           └── physics/
├── packages/
│   └── shared/
│       └── src/
└── docs/
    └── missions/
```

Chaque mission de développement significative aura son propre CDC sous `docs/missions/`.

## 13. Qualité et contraintes non fonctionnelles

Le projet doit :

- compiler sans erreur TypeScript ;
- ne pas accepter aveuglément les données clientes ;
- ne pas dépendre du framerate graphique pour la physique serveur ;
- isoler la logique de simulation du transport WebSocket ;
- permettre les tests de la physique sans navigateur ;
- permettre les tests du protocole sans rendu ;
- limiter les dépendances inutiles ;
- rester utilisable en réseau local sans Cloudflare ;
- fonctionner sur les navigateurs modernes principaux ;
- conserver une architecture suffisamment simple pour être comprise et déboguée facilement.

## 14. Tests obligatoires

### 14.1 Physique

Tests unitaires au minimum sur :

- intégration position/vitesse ;
- friction ;
- collision balle/paroi ;
- collision balle/balle ;
- résolution de pénétration ;
- entrée/refus d'entrée dans le trou.

### 14.2 Règles serveur

Tester :

- incrément du compteur après tir accepté ;
- absence d'incrément après tir refusé ;
- impossibilité de tirer après `finished` ;
- classement par nombre de coups ;
- rejet des valeurs invalides ;
- rejet d'une séquence de tir dupliquée.

### 14.3 Réseau

Tester au minimum avec deux clients :

- connexion ;
- join ;
- apparition des deux balles ;
- propagation d'un tir ;
- propagation d'une collision ;
- synchronisation des compteurs ;
- déconnexion ;
- reconnexion ;
- absence de divergence persistante entre état serveur et clients.

### 14.4 Build

Avant livraison d'une mission :

- tests automatisés réussis ;
- lint réussi s'il est configuré ;
- `tsc` réussi ;
- build client réussi ;
- build serveur réussi ;
- test manuel reproductible des fonctions modifiées.

Un test absent ou échoué signifie que la fonctionnalité concernée n'est pas considérée comme validée.

## 15. Critères de validation de la première version jouable

La V1 est validée lorsque :

1. le serveur démarre localement sans erreur ;
2. deux navigateurs peuvent rejoindre la même room ;
3. chaque navigateur possède sa propre balle ;
4. un joueur peut viser et tirer ;
5. un nouveau tir est possible pendant le mouvement ;
6. le compteur de coups est calculé par le serveur ;
7. les balles peuvent se percuter ;
8. les clients convergent vers le même état autoritaire ;
9. le serveur détecte l'arrivée dans le trou ;
10. le joueur ayant terminé ne peut plus tirer ;
11. les résultats reflètent le nombre de coups ;
12. le build complet réussit ;
13. les tests prévus réussissent ;
14. un Quick Tunnel Cloudflare permet à une seconde machine distante de rejoindre la partie à partir du lien copié.

## 16. Risques techniques identifiés

### Divergence de simulation

**Risque :** simulations différentes entre navigateurs.  
**Réponse :** serveur autoritaire ; les clients ne décident jamais de l'état final.

### Latence ressentie

**Risque :** tir peu réactif à distance.  
**Réponse :** interpolation puis prédiction locale/réconciliation si nécessaire.

### Collisions incohérentes avec latence

**Risque :** un client voit une collision légèrement différemment du serveur.  
**Réponse :** résultat serveur prioritaire et correction visuelle côté client.

### Messages malveillants ou invalides

**Risque :** client modifié ou bug navigateur.  
**Réponse :** validation complète côté serveur et limites sur les entrées.

### Tunnel temporaire indisponible

**Risque :** les Quick Tunnels ne sont pas une infrastructure de production.  
**Réponse :** conserver un fonctionnement local indépendant du tunnel ; le tunnel est une couche d'exposition et non une dépendance du moteur de jeu.

## 17. Découpage de développement recommandé

### Mission 1 — Socle multijoueur

- monorepo TypeScript ;
- React/Canvas ;
- serveur HTTP + WebSocket ;
- package partagé ;
- room ;
- deux joueurs ;
- simulation autoritaire minimale ;
- tir ;
- snapshots ;
- tests réseau de base.

### Mission 2 — Physique de golf

- parois ;
- friction ;
- collisions balle/balle ;
- trou ;
- tests physiques.

### Mission 3 — Qualité réseau

- interpolation ;
- reconnexion ;
- ping/latence ;
- prédiction locale si nécessaire ;
- réconciliation.

### Mission 4 — Boucle de jeu

- états de room ;
- résultats ;
- revanche ;
- UX de partage du lien.

### Mission 5 — Cloudflare et validation distante

- lancement simplifié de `cloudflared` ;
- récupération/affichage de l'URL ;
- bouton de copie ;
- validation entre deux machines sur Internet.

## 18. Règle de développement

Toute évolution doit suivre :

**Comprendre → Planifier → Coder → Tester → Sauvegarder → Intégrer → Valider → Livrer.**

Pour chaque mission :

- créer ou mettre à jour son CDC dédié ;
- définir les tests avant la réalisation ;
- développer par briques indépendantes ;
- ne pas avancer sur une brique nécessaire tant que son test échoue ;
- inspecter les changements avant commit ;
- créer un commit descriptif ;
- pousser sur GitHub lorsque l'accès le permet ;
- déclarer explicitement tout test, build ou push non effectué.
