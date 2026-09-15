#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.termux-golf"
PORT="${PORT:-3000}"
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-1}"
DNS_WAIT_SECONDS="${DNS_WAIT_SECONDS:-120}"
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
echo "  - attendre l'enregistrement Cloudflare"
echo "  - NE PAS utiliser le resolver DNS local de Termux"
echo "  - interroger Cloudflare DNS en HTTPS via 1.1.1.1"
echo "  - tester /health avec curl --resolve, donc sans lookup DNS local"
echo "  - ouvrir Chrome seulement quand la route publique Cloudflare repond"
echo "  - surveiller ensuite 60 s les processus et requetes HTTP/WebSocket"
echo "  - enregistrer .termux-golf/supervisor.log"
echo

echo "Ce test utilise uniquement des connexions HTTPS sortantes ordinaires depuis la sandbox Termux."
echo

exec env ROOT_DIR="$ROOT_DIR" STATE_DIR="$STATE_DIR" PORT="$PORT" \
  AUTO_OPEN_BROWSER="$AUTO_OPEN_BROWSER" DNS_WAIT_SECONDS="$DNS_WAIT_SECONDS" \
  bash "$SUPERVISOR"
