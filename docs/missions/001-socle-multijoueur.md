# Mission 001 — Socle multijoueur jouable

## Objectif

Livrer une première version technique jouable à deux navigateurs avec serveur autoritaire : rejoindre une room par URL, tirer librement, collisions balle/balle et parois, friction, trou et compteur de coups synchronisé.

## Inclus

- React + TypeScript + Canvas 2D ;
- serveur Node.js + TypeScript sur le même port que le client compilé ;
- WebSocket natif côté client et `ws` côté serveur ;
- room extraite de `/game/:roomId` ;
- identité locale par token ;
- simulation serveur fixe à 60 Hz ;
- snapshots à 20 Hz ;
- tir angle/puissance validé par le serveur ;
- tir autorisé pendant le mouvement ;
- collisions cercle/cercle et cercle/parois ;
- friction ;
- trou avec vitesse d'entrée maximale ;
- compteur de coups et état `finished` autoritaires ;
- interpolation client simple ;
- bouton de copie de l'URL ;
- reconnexion sur le même token ;
- scripts de build/test et documentation de lancement Cloudflare.

## Exclus

- prédiction/réconciliation avancée ;
- obstacles autres que les limites rectangulaires ;
- lobby complet et ready-check ;
- persistance ;
- matchmaking ;
- anti-triche avancé ;
- plusieurs trous/manches ;
- interface mobile optimisée.

## Fichiers / composants

- `packages/shared/src/*` : protocole et constantes ;
- `apps/server/src/*` : room, simulation, validation réseau, HTTP/WebSocket ;
- `apps/client/src/*` : React, Canvas, WebSocket, interpolation ;
- `tests/*` : physique et règles ;
- `README.md` : exécution locale et Quick Tunnel.

## Contraintes techniques

- le serveur est l'unique autorité sur état physique, score et arrivée ;
- aucune position/vitesse venant du client n'est acceptée ;
- pas de dépendance de la physique au framerate graphique ;
- données réseau validées avant utilisation ;
- même origine pour HTTP et WebSocket ;
- pas fixe `1/60 s`, snapshots `20 Hz`.

## Briques et tests

1. **Physique** : intégration, friction, parois, balle/balle, trou — tests unitaires.
2. **Règles** : tir valide/invalide, séquence dupliquée, score, joueur fini — tests unitaires.
3. **Réseau/room** : join, token/reconnexion, snapshot — test d'intégration minimal par WebSocket.
4. **Client** : rendu Canvas, drag de tir, copie du lien — build TypeScript/Vite.
5. **Intégration** : build complet et test manuel reproductible à deux onglets.

## Critères de validation

- `npm test` réussi ;
- `npm run typecheck` réussi ;
- `npm run build` réussi ;
- deux clients d'une même room reçoivent le même état serveur ;
- un tir incrémente exactement une fois le compteur ;
- une séquence dupliquée n'ajoute aucun coup ;
- les balles se percutent et rebondissent sur les limites ;
- un joueur entré dans le trou ne peut plus tirer ;
- l'URL `/game/<roomId>` est copiable et fonctionne via Quick Tunnel.

## Risques de régression

- boucle serveur instable sous charge ;
- tunneling WebSocket mal routé ;
- divergence visuelle due à l'interpolation ;
- reconnexion créant une seconde balle ;
- changement de constantes client/serveur non partagé.
