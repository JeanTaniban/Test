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
TUNNEL_URL=""

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
    if curl --silent --fail --connect-timeout 2 --max-time 3 "$ORIGIN/health" >/dev/null 2>&1; then
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

public_health_ok() {
  local url="$1"
  curl --silent --fail --location \
    --connect-timeout 3 --max-time 6 \
    "$url/health" 2>/dev/null | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

wait_for_public_health() {
  local url="$1"
  for _ in {1..60}; do
    if ! is_running "$SERVER_PID_FILE" || ! is_running "$TUNNEL_PID_FILE"; then
      return 1
    fi
    if public_health_ok "$url"; then
      return 0
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

  if command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "$url" -p com.android.chrome >/dev/null 2>&1; then
      return 0
    fi
  fi

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

start_tunnel_once() {
  TUNNEL_URL=""
  : > "$TUNNEL_LOG"
  echo "Demarrage du Quick Tunnel Cloudflare..."
  nohup cloudflared tunnel --url "$ORIGIN" </dev/null >>"$TUNNEL_LOG" 2>&1 &
  echo "$!" > "$TUNNEL_PID_FILE"

  local url
  url="$(wait_for_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    return 1
  fi

  echo "Tunnel attribue : $url"
  echo "Attente de la disponibilite publique..."
  if ! wait_for_public_health "$url"; then
    return 1
  fi

  TUNNEL_URL="$url"
  return 0
}

start_tunnel() {
  local attempt
  for attempt in 1 2 3; do
    if (( attempt > 1 )); then
      echo "Nouvelle tentative Cloudflare ($attempt/3)..."
    fi
    if start_tunnel_once; then
      return 0
    fi

    echo "Le tunnel n'est pas devenu joignable." >&2
    stop_pid "$TUNNEL_PID_FILE" "cloudflared" || true
    tail -n 25 "$TUNNEL_LOG" >&2 || true
    sleep 1
  done
  return 1
}

start_server() {
  cd "$ROOT_DIR"
  build_if_needed

  if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || true
  fi

  if is_running "$SERVER_PID_FILE"; then
    echo "Serveur deja actif (PID $(read_pid "$SERVER_PID_FILE"))."
  else
    : > "$SERVER_LOG"
    echo "Demarrage du serveur sur $ORIGIN..."
    nohup env PORT="$PORT" npm start </dev/null >>"$SERVER_LOG" 2>&1 &
    echo "$!" > "$SERVER_PID_FILE"
  fi

  if ! wait_for_health; then
    echo "Erreur: le serveur ne repond pas sur /health." >&2
    tail -n 30 "$SERVER_LOG" >&2 || true
    exit 1
  fi

  local url=""
  if is_running "$TUNNEL_PID_FILE"; then
    url="$(find_tunnel_url || true)"
    if [[ -n "$url" ]] && public_health_ok "$url"; then
      echo "Tunnel deja actif et joignable (PID $(read_pid "$TUNNEL_PID_FILE"))."
    else
      echo "Tunnel existant non joignable: redemarrage..."
      stop_pid "$TUNNEL_PID_FILE" "cloudflared"
      if ! start_tunnel; then
        url=""
      else
        url="$TUNNEL_URL"
      fi
    fi
  else
    if start_tunnel; then
      url="$TUNNEL_URL"
    fi
  fi

  if [[ -z "$url" ]] || ! public_health_ok "$url"; then
    echo "Erreur: aucun Quick Tunnel Cloudflare joignable n'a pu etre etabli." >&2
    echo "Le serveur local reste disponible sur $ORIGIN" >&2
    echo "Diagnostic: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi

  echo
  echo "Serveur pret et tunnel verifie."
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
  local node_state="arrete"
  local tunnel_state="arrete"
  local health_state="indisponible"
  local public_state="indisponible"

  if is_running "$SERVER_PID_FILE"; then
    node_state="actif (PID $(read_pid "$SERVER_PID_FILE"))"
  fi
  if is_running "$TUNNEL_PID_FILE"; then
    tunnel_state="actif (PID $(read_pid "$TUNNEL_PID_FILE"))"
  fi
  if curl --silent --fail --connect-timeout 2 --max-time 3 "$ORIGIN/health" >/dev/null 2>&1; then
    health_state="OK"
  fi

  local url
  url="$(find_tunnel_url || true)"
  if [[ -n "$url" ]] && public_health_ok "$url"; then
    public_state="OK"
  fi

  echo "Node         : $node_state"
  echo "cloudflared  : $tunnel_state"
  echo "Health local : $health_state"
  [[ -n "$url" ]] && echo "URL          : $url"
  [[ -n "$url" ]] && echo "Health public: $public_state"
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
  if ! public_health_ok "$url"; then
    echo "Le tunnel existe mais n'est pas joignable actuellement." >&2
    echo "Diagnostic: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi
  open_public_url "$url"
}

doctor() {
  status_server
  echo
  echo "--- Dernieres lignes serveur ---"
  tail -n 25 "$SERVER_LOG" 2>/dev/null || true
  echo
  echo "--- Dernieres lignes cloudflared ---"
  tail -n 35 "$TUNNEL_LOG" 2>/dev/null || true
  echo
  if command -v termux-wake-lock >/dev/null 2>&1; then
    echo "Wake-lock    : commande disponible"
  else
    echo "Wake-lock    : commande absente"
  fi
  echo "Si Android coupe Termux en arriere-plan, autorise l'activite en arriere-plan et desactive l'optimisation batterie pour Termux."
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
  start    demarre Node + Cloudflare, verifie le tunnel puis ouvre le navigateur
  stop     arrete le tunnel et le serveur
  restart  redemarre les deux processus et rouvre le navigateur
  status   affiche les PID et les healthchecks local/public
  doctor   affiche etat + derniers logs Node/cloudflared
  logs     suit les logs Node + cloudflared
  url      affiche uniquement l'URL trycloudflare.com
  open     verifie puis ouvre l'URL courante dans Chrome / le navigateur Android
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
  doctor) doctor ;;
  logs) show_logs ;;
  url) show_url ;;
  open) open_browser ;;
  update) update_project ;;
  *) usage; exit 1 ;;
esac
