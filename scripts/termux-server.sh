#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.termux-golf"
PORT="${PORT:-3000}"
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-1}"
PUBLIC_READY_WAIT_SECONDS="${PUBLIC_READY_WAIT_SECONDS:-${DNS_WAIT_SECONDS:-120}}"
ORIGIN="http://127.0.0.1:$PORT"
SERVER_ENTRY="$ROOT_DIR/dist/server/apps/server/src/index.js"
CLIENT_ENTRY="$ROOT_DIR/apps/client/dist/index.html"
DNS_HELPER="$ROOT_DIR/scripts/termux-dns.sh"
WATCHDOG_SCRIPT="$ROOT_DIR/scripts/termux-watchdog.sh"
DIAG_SCRIPT="$ROOT_DIR/scripts/termux-diagnose.sh"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog.pid"
SERVER_LOG="$STATE_DIR/server.log"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
WATCHDOG_LOG="$STATE_DIR/watchdog.log"
TUNNEL_URL=""

mkdir -p "$STATE_DIR"
source "$DNS_HELPER"

now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
event_log() { printf '[%s] %s\n' "$(now)" "$*" >> "$WATCHDOG_LOG"; }
read_pid() { [[ -f "$1" ]] && cat "$1" || true; }

is_running() {
  local pid
  pid="$(read_pid "$1")"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

stop_pid() {
  local file="$1" label="$2" pid
  pid="$(read_pid "$file")"
  [[ -n "$pid" ]] || { rm -f "$file"; return 0; }
  if kill -0 "$pid" 2>/dev/null; then
    echo "Arret de $label (PID $pid)..."
    kill "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$file"
}

build_if_needed() {
  if [[ ! -f "$SERVER_ENTRY" || ! -f "$CLIENT_ENTRY" ]]; then
    echo "Build absent: compilation du projet..."
    (cd "$ROOT_DIR" && npm run build)
  fi
}

wait_local_health() {
  for _ in {1..30}; do
    curl --silent --fail --connect-timeout 1 --max-time 2 "$ORIGIN/health" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}

find_tunnel_url() {
  [[ -f "$TUNNEL_LOG" ]] || return 1
  grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1
}

wait_tunnel_url() {
  local url
  for _ in {1..40}; do
    url="$(find_tunnel_url || true)"
    [[ -n "$url" ]] && { printf '%s\n' "$url"; return 0; }
    is_running "$TUNNEL_PID_FILE" || return 1
    sleep 0.5
  done
  return 1
}

tunnel_registered() {
  is_running "$TUNNEL_PID_FILE" \
    && [[ -f "$TUNNEL_LOG" ]] \
    && grep -q 'Registered tunnel connection' "$TUNNEL_LOG"
}

wait_tunnel_registered() {
  for _ in {1..90}; do
    tunnel_registered && return 0
    is_running "$TUNNEL_PID_FILE" || return 1
    sleep 0.5
  done
  return 1
}

check_quick_tunnel_config() {
  local path
  for path in "$HOME/.cloudflared/config.yml" "$HOME/.cloudflared/config.yaml"; do
    if [[ -f "$path" ]]; then
      echo "Erreur: Quick Tunnel incompatible avec le fichier $path" >&2
      return 1
    fi
  done
}

start_watchdog() {
  is_running "$WATCHDOG_PID_FILE" && return 0
  [[ -f "$WATCHDOG_SCRIPT" ]] || return 0
  nohup env ROOT_DIR="$ROOT_DIR" STATE_DIR="$STATE_DIR" PORT="$PORT" ORIGIN="$ORIGIN" \
    bash "$WATCHDOG_SCRIPT" </dev/null >>"$WATCHDOG_LOG" 2>&1 &
  echo "$!" > "$WATCHDOG_PID_FILE"
}

open_public_url() {
  local url="$1"
  echo "Ouverture du jeu dans le navigateur..."
  event_log "opening browser url=$url"
  if command -v am >/dev/null 2>&1 && am start -a android.intent.action.VIEW -d "$url" -p com.android.chrome >/dev/null 2>&1; then
    return 0
  fi
  if command -v termux-open-url >/dev/null 2>&1 && termux-open-url "$url" >/dev/null 2>&1; then
    return 0
  fi
  if command -v am >/dev/null 2>&1 && am start -a android.intent.action.VIEW -d "$url" >/dev/null 2>&1; then
    return 0
  fi
  echo "Ouverture automatique impossible. URL: $url" >&2
}

start_tunnel() {
  check_quick_tunnel_config
  : > "$TUNNEL_LOG"
  echo "Demarrage du Quick Tunnel Cloudflare..."
  nohup cloudflared tunnel --url "$ORIGIN" </dev/null >>"$TUNNEL_LOG" 2>&1 &
  echo "$!" > "$TUNNEL_PID_FILE"
  event_log "cloudflared launched pid=$! origin=$ORIGIN"

  local url
  url="$(wait_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    echo "Erreur: aucune URL Quick Tunnel." >&2
    tail -n 60 "$TUNNEL_LOG" >&2 || true
    return 1
  fi
  echo "Tunnel attribue : $url"
  echo "Attente de l'enregistrement du connecteur Cloudflare..."
  if ! wait_tunnel_registered; then
    echo "Erreur: connecteur Cloudflare non enregistre." >&2
    tail -n 80 "$TUNNEL_LOG" >&2 || true
    return 1
  fi
  TUNNEL_URL="$url"
  echo "Connecteur Cloudflare enregistre."
}

get_or_start_tunnel() {
  if is_running "$TUNNEL_PID_FILE"; then
    local url
    url="$(find_tunnel_url || true)"
    if [[ -n "$url" ]] && wait_tunnel_registered; then
      TUNNEL_URL="$url"
      echo "cloudflared deja actif (PID $(read_pid "$TUNNEL_PID_FILE"))."
      return 0
    fi
    echo "cloudflared existe mais n'est pas pret; il est conserve pour diagnostic." >&2
    return 1
  fi
  start_tunnel
}

wait_public_route() {
  local url="$1"
  echo "Validation publique sans utiliser le DNS local de Termux..."
  echo "  1) DNS-over-HTTPS Cloudflare via 1.1.1.1/1.0.0.1"
  echo "  2) HTTPS /health avec curl --resolve"
  wait_for_quick_tunnel_public_ready "$url" "$PUBLIC_READY_WAIT_SECONDS" READY
}

start_server() {
  cd "$ROOT_DIR"
  build_if_needed
  printf '\n[%s] ===== START SESSION =====\n' "$(now)" >> "$WATCHDOG_LOG"

  command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock >/dev/null 2>&1 || true

  if ! is_running "$SERVER_PID_FILE"; then
    : > "$SERVER_LOG"
    echo "Demarrage du serveur sur $ORIGIN..."
    nohup env PORT="$PORT" SERVER_DIAGNOSTICS=1 node "$SERVER_ENTRY" </dev/null >>"$SERVER_LOG" 2>&1 &
    echo "$!" > "$SERVER_PID_FILE"
    event_log "node launched pid=$!"
  else
    echo "Serveur deja actif (PID $(read_pid "$SERVER_PID_FILE"))."
  fi

  start_watchdog

  if ! wait_local_health; then
    echo "Erreur: /health local ne repond pas." >&2
    tail -n 80 "$SERVER_LOG" >&2 || true
    exit 1
  fi
  echo "Health local : OK"

  if ! get_or_start_tunnel; then
    echo "Le serveur local reste actif. Lance doctor pour le diagnostic." >&2
    exit 1
  fi

  local url="$TUNNEL_URL"
  if ! wait_public_route "$url"; then
    echo >&2
    echo "La route publique n'est pas encore verifiee apres ${PUBLIC_READY_WAIT_SECONDS}s." >&2
    echo "Node et cloudflared restent actifs; aucune nouvelle URL n'est creee." >&2
    echo "Le test n'utilise pas le resolver DNS local de Termux." >&2
    exit 1
  fi

  event_log "public route ready url=$url"
  echo
  echo "Serveur pret et route publique verifiee."
  echo "URL publique : $url"
  echo "URL locale   : $ORIGIN"
  echo "Readiness    : Cloudflare DoH + HTTPS forcee OK"

  if [[ "$AUTO_OPEN_BROWSER" != "0" ]]; then
    open_public_url "$url"
  fi
}

stop_server() {
  event_log "stop requested"
  stop_pid "$WATCHDOG_PID_FILE" "watchdog"
  stop_pid "$TUNNEL_PID_FILE" "cloudflared"
  stop_pid "$SERVER_PID_FILE" "serveur Node"
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock >/dev/null 2>&1 || true
  echo "Serveur arrete."
}

status_server() {
  local node_state="arrete" tunnel_state="arrete" watchdog_state="arrete"
  local connector_state="non enregistre" local_health="indisponible"
  local publication="inconnue" public_health="indisponible" edge_ip=""

  is_running "$SERVER_PID_FILE" && node_state="actif (PID $(read_pid "$SERVER_PID_FILE"))"
  is_running "$TUNNEL_PID_FILE" && tunnel_state="actif (PID $(read_pid "$TUNNEL_PID_FILE"))"
  is_running "$WATCHDOG_PID_FILE" && watchdog_state="actif (PID $(read_pid "$WATCHDOG_PID_FILE"))"
  tunnel_registered && connector_state="enregistre"
  curl --silent --fail --connect-timeout 1 --max-time 2 "$ORIGIN/health" >/dev/null 2>&1 && local_health="OK"

  local url host addresses
  url="$(find_tunnel_url || true)"
  if [[ -n "$url" ]]; then
    host="${url#https://}"; host="${host%%/*}"
    addresses="$(cloudflare_doh_lookup_a "$host" 2>/dev/null || true)"
    [[ -n "$addresses" ]] && publication="publiee par Cloudflare DoH"
    edge_ip="$(quick_tunnel_public_health "$url" 2>/dev/null || true)"
    [[ -n "$edge_ip" ]] && public_health="OK via $edge_ip"
  fi

  echo "Node              : $node_state"
  echo "cloudflared       : $tunnel_state"
  echo "Watchdog          : $watchdog_state"
  echo "Connecteur CF     : $connector_state"
  echo "Health local      : $local_health"
  [[ -n "$url" ]] && echo "URL               : $url"
  [[ -n "$url" ]] && echo "Publication CF DNS: $publication"
  [[ -n "$url" ]] && echo "Health public     : $public_health"
  echo "Resolver Termux   : non utilise pour la readiness"
}

show_logs() {
  touch "$SERVER_LOG" "$TUNNEL_LOG" "$WATCHDOG_LOG"
  tail -n 120 -F "$SERVER_LOG" "$TUNNEL_LOG" "$WATCHDOG_LOG"
}

show_url() {
  local url
  url="$(find_tunnel_url || true)"
  [[ -n "$url" ]] || { echo "Aucune URL Cloudflare disponible." >&2; exit 1; }
  echo "$url"
}

open_browser() {
  local url
  url="$(find_tunnel_url || true)"
  [[ -n "$url" ]] || { echo "Aucune URL Cloudflare disponible." >&2; exit 1; }
  tunnel_registered || { echo "Connecteur Cloudflare non enregistre." >&2; exit 1; }
  if ! quick_tunnel_public_health "$url" >/dev/null 2>&1; then
    echo "Route publique non verifiee par Cloudflare DoH + curl --resolve." >&2
    exit 1
  fi
  open_public_url "$url"
}

doctor() {
  [[ -f "$DIAG_SCRIPT" ]] || { echo "Script diagnostic absent." >&2; exit 1; }
  env ROOT_DIR="$ROOT_DIR" STATE_DIR="$STATE_DIR" PORT="$PORT" ORIGIN="$ORIGIN" bash "$DIAG_SCRIPT"
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
  start    demarre Node + Quick Tunnel, verifie la route publique sans DNS Termux, ouvre Chrome
  stop     arrete watchdog, tunnel et serveur
  restart  stop puis start
  status   affiche processus, connecteur et readiness Cloudflare
  doctor   genere le rapport diagnostic
  logs     suit les logs en direct
  url      affiche l'URL publique
  open     ouvre l'URL si la route publique est verifiee
  update   git pull + npm install + build + start

Variables:
  AUTO_OPEN_BROWSER=0          ne pas ouvrir Chrome automatiquement
  PUBLIC_READY_WAIT_SECONDS=120 delai max de readiness publique
  PORT=3000                    port local
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
