#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.termux-golf"
PORT="${PORT:-3000}"
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-1}"
SUPERVISOR="$ROOT_DIR/scripts/termux-supervise.sh"

mkdir -p "$STATE_DIR"
cd "$ROOT_DIR"

echo "=== Multiplayer Golf / Termux DEBUG ==="
echo "Arret des anciens processus..."
bash "$ROOT_DIR/scripts/termux-server.sh" stop >/dev/null 2>&1 || true

echo "Rebuild pour etre certain que les logs serveur sont a jour..."
npm run build

if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock >/dev/null 2>&1 || true
fi

echo
echo "Le mode debug va:"
echo "  - lancer Node et cloudflared sous un superviseur"
echo "  - ouvrir Chrome"
echo "  - rester actif 60 s"
echo "  - afficher les requetes HTTP/WebSocket en temps reel"
echo "  - afficher le code de sortie si Node/cloudflared meurt"
echo "  - enregistrer .termux-golf/supervisor.log"
echo

echo "Si Chrome dit 'site inaccessible', reviens immediatement dans Termux sans relancer quoi que ce soit."
echo

exec env ROOT_DIR="$ROOT_DIR" STATE_DIR="$STATE_DIR" PORT="$PORT" AUTO_OPEN_BROWSER="$AUTO_OPEN_BROWSER" bash "$SUPERVISOR"
