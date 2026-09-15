#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.termux-golf"
PORT="${PORT:-3000}"
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-1}"
DNS_WAIT_SECONDS="${DNS_WAIT_SECONDS:-120}"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog.pid"
SERVER_LOG="$STATE_DIR/server.log"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
WATCHDOG_LOG="$STATE_DIR/watchdog.log"
ORIGIN="http://127.0.0.1:$PORT"
SERVER_ENTRY="$ROOT_DIR/dist/server/apps/server/src/index.js"
CLIENT_ENTRY="$ROOT_DIR/apps/client/dist/index.html"
WATCHDOG_SCRIPT="$ROOT_DIR/scripts/termux-watchdog.sh"
DIAG_SCRIPT="$ROOT_DIR/scripts/termux-diagnose.sh"
DNS_HELPER="$ROOT_DIR/scripts/termux-dns.sh"
TUNNEL_URL=""

mkdir -p "$STATE_DIR"
source "$DNS_HELPER"

now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

event_log() {
  printf '[%s] %s\n' "$(now)" "$*" >> "$WATCHDOG_LOG"
}

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

start_watchdog() {
  if is_running "$WATCHDOG_PID_FILE"; then
    return 0
  fi
  if [[ ! -f "$WATCHDOG_SCRIPT" ]]; then
    return 0
  fi

  event_log "manager starting watchdog"
  nohup env ROOT_DIR="$ROOT_DIR" STATE_DIR="$STATE_DIR" PORT="$PORT" ORIGIN="$ORIGIN" \
    bash "$WATCHDOG_SCRIPT" </dev/null >>"$WATCHDOG_LOG" 2>&1 &
  echo "$!" > "$WATCHDOG_PID_FILE"
}

stop_watchdog() {
  stop_pid "$WATCHDOG_PID_FILE" "watchdog" || true
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

tunnel_registered() {
  is_running "$TUNNEL_PID_FILE" \
    && [[ -f "$TUNNEL_LOG" ]] \
    && grep -q 'Registered tunnel connection' "$TUNNEL_LOG"
}

wait_for_tunnel_registered() {
  for _ in {1..90}; do
    if tunnel_registered; then
      return 0
    fi
    if ! is_running "$TUNNEL_PID_FILE"; then
      return 1
    fi
    sleep 0.5
  done
  return 1
}

wait_for_public_health() {
  local url="$1"
  local elapsed=0
  while (( elapsed <= 60 )); do
    if public_health_via_system_dns "$url"; then
      return 0
    fi
    if ! tunnel_registered; then
      return 1
    fi
    if (( elapsed % 10 == 0 )); then
      echo "Attente du /health public... ${elapsed}s"
      event_log "waiting public health elapsed=${elapsed}s url=$url"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

quick_tunnel_config_path() {
  local path
  for path in "$HOME/.cloudflared/config.yml" "$HOME/.cloudflared/config.yaml"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

check_quick_tunnel_config() {
  local config_path
  config_path="$(quick_tunnel_config_path || true)"
  if [[ -n "$config_path" ]]; then
    echo "Erreur: Cloudflare ne supporte pas Quick Tunnel avec ce fichier present:" >&2
    echo "  $config_path" >&2
    echo "Renomme-le temporairement puis relance le serveur." >&2
    return 1
  fi
  return 0
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
  event_log "manager opening browser url=$url"

  if command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "$url" -p com.android.chrome >/dev/null 2>&1; then
      event_log "browser launch via Chrome intent succeeded"
      return 0
    fi
  fi

  if command -v termux-open-url >/dev/null 2>&1; then
    if termux-open-url "$url" >/dev/null 2>&1; then
      event_log "browser launch via termux-open-url succeeded"
      return 0
    fi
  fi

  if command -v am >/dev/null 2>&1; then
    if am start -a android.intent.action.VIEW -d "$url" >/dev/null 2>&1; then
      event_log "browser launch via generic Android intent succeeded"
      return 0
    fi
  fi

  event_log "browser automatic launch failed"
  echo "Impossible d'ouvrir automatiquement le navigateur. Ouvre manuellement : $url" >&2
  return 0
}

start_new_tunnel() {
  TUNNEL_URL=""
  check_quick_tunnel_config

  : > "$TUNNEL_LOG"
  echo "Demarrage du Quick Tunnel Cloudflare..."
  event_log "manager starting cloudflared origin=$ORIGIN"
  nohup cloudflared tunnel --url "$ORIGIN" </dev/null >>"$TUNNEL_LOG" 2>&1 &
  echo "$!" > "$TUNNEL_PID_FILE"
  event_log "cloudflared launched pid=$(read_pid "$TUNNEL_PID_FILE")"

  local url
  url="$(wait_for_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    event_log "cloudflared did not provide Quick Tunnel URL"
    echo "Erreur: cloudflared n'a pas fourni d'URL Quick Tunnel." >&2
    tail -n 35 "$TUNNEL_LOG" >&2 || true
    return 1
  fi

  event_log "cloudflared assigned url=$url"
  echo "Tunnel attribue : $url"
  echo "Attente de l'enregistrement du connecteur Cloudflare..."
  if ! wait_for_tunnel_registered; then
    event_log "cloudflared failed to reach Registered tunnel connection"
    echo "Erreur: cloudflared n'a pas enregistre de connexion au reseau Cloudflare." >&2
    echo "Le processus n'est pas tue automatiquement: cloudflared sait gerer ses reconnexions." >&2
    tail -n 35 "$TUNNEL_LOG" >&2 || true
    return 1
  fi

  TUNNEL_URL="$url"
  event_log "cloudflared connector registered pid=$(read_pid "$TUNNEL_PID_FILE") url=$url"
  echo "Connecteur Cloudflare enregistre."
  return 0
}

get_or_start_tunnel() {
  TUNNEL_URL=""

  if is_running "$TUNNEL_PID_FILE"; then
    local url
    url="$(find_tunnel_url || true)"
    if [[ -n "$url" ]]; then
      echo "cloudflared deja actif (PID $(read_pid "$TUNNEL_PID_FILE"))."
      echo "Attente de l'enregistrement du connecteur existant..."
      if wait_for_tunnel_registered; then
        TUNNEL_URL="$url"
        return 0
      fi
    fi

    echo "cloudflared est actif mais pas encore enregistre." >&2
    echo "Je le conserve au lieu de recreer un Quick Tunnel." >&2
    echo "Diagnostic: bash scripts/termux-server.sh doctor" >&2
    return 1
  fi

  start_new_tunnel
}

start_server() {
  cd "$ROOT_DIR"
  build_if_needed

  printf '\n[%s] ===== START SESSION =====\n' "$(now)" >> "$WATCHDOG_LOG"
  event_log "manager start requested commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown) port=$PORT"

  if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || true
    event_log "termux-wake-lock requested"
  fi

  if is_running "$SERVER_PID_FILE"; then
    echo "Serveur deja actif (PID $(read_pid "$SERVER_PID_FILE"))."
  else
    : > "$SERVER_LOG"
    echo "Demarrage du serveur sur $ORIGIN..."
    nohup env PORT="$PORT" SERVER_DIAGNOSTICS=1 node "$SERVER_ENTRY" </dev/null >>"$SERVER_LOG" 2>&1 &
    echo "$!" > "$SERVER_PID_FILE"
    event_log "node launched pid=$(read_pid "$SERVER_PID_FILE") entry=$SERVER_ENTRY"
  fi

  start_watchdog

  if ! wait_for_health; then
    event_log "local health failed during startup"
    echo "Erreur: le serveur ne repond pas sur /health." >&2
    tail -n 40 "$SERVER_LOG" >&2 || true
    echo "Diagnostic complet: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi
  event_log "local health OK"

  if ! get_or_start_tunnel; then
    event_log "tunnel startup/registration failed"
    echo "Le serveur local reste actif sur $ORIGIN." >&2
    echo "Diagnostic complet: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi

  local url="$TUNNEL_URL"
  echo "Attente de la publication DNS du Quick Tunnel..."
  if ! wait_for_quick_tunnel_dns "$url" "$DNS_WAIT_SECONDS" DNS; then
    event_log "system DNS unresolved after ${DNS_WAIT_SECONDS}s url=$url"
    echo >&2
    if cloudflare_doh_supported && public_health_via_cloudflare_doh "$url"; then
      echo "Erreur DNS locale: Cloudflare 1.1.1.1 voit le tunnel, mais le DNS Android/Termux ne le resout pas." >&2
      echo "Le serveur et le tunnel restent actifs. Verifie Private DNS / bloqueur DNS / VPN sur Android." >&2
      event_log "Cloudflare DoH healthy while system DNS unresolved"
    else
      echo "Le hostname trycloudflare.com n'est pas encore publiquement resolvable apres ${DNS_WAIT_SECONDS}s." >&2
      echo "Le serveur et le tunnel restent actifs; aucune nouvelle URL n'est creee." >&2
      event_log "Cloudflare DoH also not ready"
    fi
    echo "Chrome n'est pas ouvert avec un hostname non resolvable." >&2
    echo "Diagnostic: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi
  event_log "system DNS ready url=$url"

  echo "DNS OK. Attente de la reponse publique /health..."
  if ! wait_for_public_health "$url"; then
    event_log "public health unavailable despite DNS readiness url=$url"
    echo "Erreur: le DNS resout le tunnel mais /health public n'est pas encore disponible." >&2
    echo "Le tunnel reste actif. Diagnostic: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi
  event_log "public health OK url=$url"

  echo
  echo "Serveur pret et URL publique verifiee."
  echo "URL publique : $url"
  echo "URL locale   : $ORIGIN"
  echo "DNS          : OK"
  echo "Health public: OK"

  if [[ "$AUTO_OPEN_BROWSER" != "0" ]]; then
    open_public_url "$url"
    sleep 2
    if ! is_running "$SERVER_PID_FILE"; then
      event_log "ALERT node died within 2s after browser launch"
      echo "ALERTE: le processus Node s'est arrete juste apres l'ouverture du navigateur." >&2
      echo "Lance: bash scripts/termux-server.sh doctor" >&2
    fi
    if ! is_running "$TUNNEL_PID_FILE"; then
      event_log "ALERT cloudflared died within 2s after browser launch"
      echo "ALERTE: cloudflared s'est arrete juste apres l'ouverture du navigateur." >&2
      echo "Lance: bash scripts/termux-server.sh doctor" >&2
    fi
  fi
}

stop_server() {
  event_log "manager stop requested"
  stop_watchdog
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
  local watchdog_state="arrete"
  local connector_state="non enregistre"
  local health_state="indisponible"
  local dns_state="indisponible"
  local public_state="indisponible"

  if is_running "$SERVER_PID_FILE"; then
    node_state="actif (PID $(read_pid "$SERVER_PID_FILE"))"
  fi
  if is_running "$TUNNEL_PID_FILE"; then
    tunnel_state="actif (PID $(read_pid "$TUNNEL_PID_FILE"))"
  fi
  if is_running "$WATCHDOG_PID_FILE"; then
    watchdog_state="actif (PID $(read_pid "$WATCHDOG_PID_FILE"))"
  fi
  if tunnel_registered; then
    connector_state="enregistre"
  fi
  if curl --silent --fail --connect-timeout 2 --max-time 3 "$ORIGIN/health" >/dev/null 2>&1; then
    health_state="OK"
  fi

  local url host
  url="$(find_tunnel_url || true)"
  if [[ -n "$url" ]]; then
    host="${url#https://}"
    host="${host%%/*}"
    if system_dns_lookup "$host" >/dev/null 2>&1; then
      dns_state="OK"
    elif cloudflare_doh_supported && public_health_via_cloudflare_doh "$url"; then
      dns_state="echec local; 1.1.1.1 OK"
    else
      dns_state="non resolu"
    fi

    if public_health_via_system_dns "$url"; then
      public_state="OK"
    elif tunnel_registered; then
      public_state="indisponible"
    fi
  fi

  echo "Node          : $node_state"
  echo "cloudflared   : $tunnel_state"
  echo "Watchdog      : $watchdog_state"
  echo "Connecteur CF : $connector_state"
  echo "Health local  : $health_state"
  [[ -n "$url" ]] && echo "URL           : $url"
  [[ -n "$url" ]] && echo "DNS URL       : $dns_state"
  [[ -n "$url" ]] && echo "Health public : $public_state"
}

show_logs() {
  touch "$SERVER_LOG" "$TUNNEL_LOG" "$WATCHDOG_LOG"
  tail -n 120 -F "$SERVER_LOG" "$TUNNEL_LOG" "$WATCHDOG_LOG"
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
  local url host
  url="$(find_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    echo "Aucune URL Cloudflare disponible. Lancez d'abord: bash scripts/termux-server.sh start" >&2
    exit 1
  fi
  if ! tunnel_registered; then
    echo "Le connecteur cloudflared n'est pas encore enregistre." >&2
    echo "Diagnostic: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi
  host="${url#https://}"
  host="${host%%/*}"
  if ! system_dns_lookup "$host" >/dev/null 2>&1; then
    echo "Le hostname $host n'est pas resolvable par Android/Termux; navigateur non ouvert." >&2
    exit 1
  fi
  if ! public_health_via_system_dns "$url"; then
    echo "Le hostname se resout mais /health public ne repond pas encore; navigateur non ouvert." >&2
    exit 1
  fi
  open_public_url "$url"
}

doctor() {
  if [[ ! -f "$DIAG_SCRIPT" ]]; then
    echo "Script diagnostic absent: $DIAG_SCRIPT" >&2
    exit 1
  fi
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
  start    demarre Node + Quick Tunnel, attend DNS + /health public, puis ouvre Chrome
  stop     arrete watchdog, tunnel et serveur
  restart  redemarre tous les processus et rouvre le navigateur
  status   affiche processus, connecteur, DNS et healthchecks
  doctor   genere un rapport diagnostic complet et le sauvegarde dans .termux-golf/
  logs     suit en direct server.log + tunnel.log + watchdog.log
  url      affiche uniquement l'URL trycloudflare.com
  open     ouvre l'URL seulement si DNS et /health public sont prets
  update   git pull, reinstalle, rebuild puis redemarre

Variables:
  AUTO_OPEN_BROWSER=0  ne pas ouvrir automatiquement le navigateur au start
  DNS_WAIT_SECONDS=120 delai max de resolution DNS avant de rendre la main
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
