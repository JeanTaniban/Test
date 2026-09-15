# Mission 003 — Build Termux robuste + ouverture navigateur

## Contexte

Le build serveur initial utilisait directement le CLI `esbuild`. Sur Termux/Android ARM64, une installation réelle a produit l'erreur :

```text
Must use "outdir" when there are multiple input files
```

Le client Vite compilait correctement, mais le serveur ne pouvait donc pas être produit et le gestionnaire Termux relançait inutilement le même build en échec.

## Objectifs

- supprimer la dépendance au CLI natif esbuild pour le build serveur de production ;
- compiler le serveur avec TypeScript de manière portable ;
- vérifier que l'artefact compilé démarre réellement ;
- conserver le build Vite du client ;
- ouvrir automatiquement le premier client dans Chrome après obtention du Quick Tunnel ;
- fournir une commande `open` et un moyen de désactiver l'ouverture automatique.

## Architecture retenue

Le build serveur utilise `tsc` avec `tsconfig.server.json` et produit du CommonJS isolé sous `dist/server/`. Le fichier `dist/server/package.json` force `type=commonjs` afin que le `type=module` du package racine n'affecte pas l'artefact serveur.

Le point d'entrée de production devient :

```text
dist/server/apps/server/src/index.js
```

Un smoke test démarre cet artefact et interroge `/health`.

## Termux

Après création de l'URL `trycloudflare.com`, le gestionnaire tente dans cet ordre :

1. Android Activity Manager avec le package `com.android.chrome` ;
2. `termux-open-url` ;
3. gestionnaire Android générique `VIEW`.

L'ouverture automatique est désactivable avec :

```bash
AUTO_OPEN_BROWSER=0 bash scripts/termux-server.sh start
```

Une commande manuelle est ajoutée :

```bash
bash scripts/termux-server.sh open
```

## Validation

La CI doit réussir :

- installation npm ;
- syntaxe Bash ;
- tests existants ;
- typecheck ;
- build client ;
- build serveur TypeScript ;
- smoke test du serveur compilé sur `/health`.

La validation finale Termux devra être confirmée sur Android ARM64 en exécutant le script d'installation et `start`.
