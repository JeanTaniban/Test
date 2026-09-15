#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.termux-golf"
PORT="${PORT:-3000}"
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-1}"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"
SERVER_LOG="$STATE_DIR/server.log"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
ORIGIN="http://127.0.0.1:$PORT"
SERVER_ENTRY="$ROOT_DIR/dist/server/apps/server/src/index.js"
CLIENT_ENTRY="$ROOT_DIR/apps/client/dist/index.html"

mkdir -p "$STATE_DIR"

read_pid() {
  local file="$1"
  [[ -f "$file" ]] && cat "$file" || true
}

is_running() {
  local file="$1"
  local pid
  pid="$(read_pid "$file")"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

stop_pid() {
  local file="$1"
  local label="$2"
  local pid
  pid="$(read_pid "$file")"
  if [[ -z "$pid" ]]; then
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    echo "Arret de $label (PID $pid)..."
    kill "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$file"
}

wait_for_health() {
  for _ in {1..30}; do
    if curl --silent --fail "$ORIGIN/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

find_tunnel_url() {
  [[ -f "$TUNNEL_LOG" ]] || return 1
  grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1
}

wait_for_tunnel_url() {
  local url
  for _ in {1..40}; do
    url="$(find_tunnel_url || true)"
    if [[ -n "$url" ]]; then
      printf '%s\n' "$url"
      return 0
    fi
    if ! is_running "$TUNNEL_PID_FILE"; then
      return 1
    fi
    sleep 0.5
  done
  return 1
}

build_if_needed() {
  if [[ ! -f "$SERVER_ENTRY" || ! -f "$CLIENT_ENTRY" ]]; then
    echo "Build absent: compilation du projet..."
    (cd "$ROOT_DIR" && npm run build)
  fi
}

open_public_url() {
  local url="$1"
  echo "Ouverture du jeu dans le navigateur..."

  # Prefer Chrome explicitly when installed. Android's Activity Manager is
  # available from Termux without requiring the Termux:API application.
  if command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "$url" -p com.android.chrome >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Fall back to Termux's URL opener, then to Android's default VIEW handler.
  if command -v termux-open-url >/dev/null 2>&1; then
    if termux-open-url "$url" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "$url" >/dev/null 2>&1; then
      return 0
    fi
  fi

  echo "Impossible d'ouvrir automatiquement le navigateur. Ouvre manuellement : $url" >&2
  return 0
}

start_server() {
  cd "$ROOT_DIR"
  build_if_needed

  if is_running "$SERVER_PID_FILE"; then
    echo "Serveur deja actif (PID $(read_pid "$SERVER_PID_FILE"))."
  else
    : > "$SERVER_LOG"
    if command -v termux-wake-lock >/dev/null 2>&1; then
      termux-wake-lock >/dev/null 2>&1 || true
    fi
    echo "Demarrage du serveur sur $ORIGIN..."
    nohup env PORT="$PORT" npm start >>"$SERVER_LOG" 2>&1 &
    echo "$!" > "$SERVER_PID_FILE"
  fi

  if ! wait_for_health; then
    echo "Erreur: le serveur ne repond pas sur /health." >&2
    tail -n 30 "$SERVER_LOG" >&2 || true
    exit 1
  fi

  if is_running "$TUNNEL_PID_FILE"; then
    echo "Tunnel deja actif (PID $(read_pid "$TUNNEL_PID_FILE"))."
  else
    : > "$TUNNEL_LOG"
    echo "Demarrage du Quick Tunnel Cloudflare..."
    nohup cloudflared tunnel --url "$ORIGIN" >>"$TUNNEL_LOG" 2>&1 &
    echo "$!" > "$TUNNEL_PID_FILE"
  fi

  local url
  url="$(wait_for_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    echo "Le serveur local fonctionne, mais l'URL Cloudflare n'a pas ete obtenue." >&2
    echo "Dernieres lignes cloudflared:" >&2
    tail -n 30 "$TUNNEL_LOG" >&2 || true
    exit 1
  fi

  echo
  echo "Serveur pret."
  echo "URL publique : $url"
  echo "URL locale   : $ORIGIN"

  if [[ "$AUTO_OPEN_BROWSER" != "0" ]]; then
    open_public_url "$url"
  fi
}

stop_server() {
  stop_pid "$TUNNEL_PID_FILE" "cloudflared"
  stop_pid "$SERVER_PID_FILE" "serveur Node"
  if command -v termux-wake-unlock >/dev/null 2>&1; then
    termux-wake-unlock >/dev/null 2>&1 || true
  fi
  echo "Serveur arrete."
}

status_server() {
  if is_running "$SERVER_PID_FILE"; then
    echo "Node       : actif (PID $(read_pid "$SERVER_PID_FILE"))"
  else
    echo "Node       : arrete"
  fi
  if is_running "$TUNNEL_PID_FILE"; then
    echo "cloudflared: actif (PID $(read_pid "$TUNNEL_PID_FILE"))"
  else
    echo "cloudflared: arrete"
  fi
  if curl --silent --fail "$ORIGIN/health" >/dev/null 2>&1; then
    echo "Health     : OK"
  else
    echo "Health     : indisponible"
  fi
  local url
  url="$(find_tunnel_url || true)"
  [[ -n "$url" ]] && echo "URL        : $url"
}

show_logs() {
  touch "$SERVER_LOG" "$TUNNEL_LOG"
  tail -n 80 -F "$SERVER_LOG" "$TUNNEL_LOG"
}

show_url() {
  local url
  url="$(find_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    echo "Aucune URL Cloudflare disponible. Lancez d'abord: bash scripts/termux-server.sh start" >&2
    exit 1
  fi
  echo "$url"
}

open_browser() {
  local url
  url="$(find_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    echo "Aucune URL Cloudflare disponible. Lancez d'abord: bash scripts/termux-server.sh start" >&2
    exit 1
  fi
  open_public_url "$url"
}

update_project() {
  stop_server
  cd "$ROOT_DIR"
  git pull --ff-only
  npm install --no-audit --no-fund
  npm run build
  start_server
}

usage() {
  cat <<'EOF'
Usage: bash scripts/termux-server.sh <commande>

Commandes:
  start    demarre Node + Cloudflare et ouvre le premier client dans Chrome
  stop     arrete le tunnel et le serveur
  restart  redemarre les deux processus et rouvre le navigateur
  status   affiche les PID, le healthcheck et l'URL
  logs     suit les logs Node + cloudflared
  url      affiche uniquement l'URL trycloudflare.com
  open     ouvre l'URL courante dans Chrome / le navigateur Android
  update   git pull, reinstalle, rebuild puis redemarre

Variables:
  AUTO_OPEN_BROWSER=0  ne pas ouvrir automatiquement le navigateur au start
  PORT=3000            changer le port local du serveur
EOF
}

case "${1:-}" in
  start) start_server ;;
  stop) stop_server ;;
  restart) stop_server; start_server ;;
  status) status_server ;;
  logs) show_logs ;;
  url) show_url ;;
  open) open_browser ;;
  update) update_project ;;
  *) usage; exit 1 ;;
esac
