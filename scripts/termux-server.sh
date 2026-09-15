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

public_health_ok() {
  local url="$1"
  curl --silent --fail --location \
    --connect-timeout 2 --max-time 3 \
    "$url/health" 2>/dev/null | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

wait_for_public_health_soft() {
  local url="$1"
  for _ in {1..8}; do
    if public_health_ok "$url"; then
      return 0
    fi
    if ! tunnel_registered; then
      return 1
    fi
    sleep 0.5
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

start_new_tunnel() {
  TUNNEL_URL=""
  check_quick_tunnel_config

  : > "$TUNNEL_LOG"
  echo "Demarrage du Quick Tunnel Cloudflare..."
  nohup cloudflared tunnel --url "$ORIGIN" </dev/null >>"$TUNNEL_LOG" 2>&1 &
  echo "$!" > "$TUNNEL_PID_FILE"

  local url
  url="$(wait_for_tunnel_url || true)"
  if [[ -z "$url" ]]; then
    echo "Erreur: cloudflared n'a pas fourni d'URL Quick Tunnel." >&2
    tail -n 35 "$TUNNEL_LOG" >&2 || true
    return 1
  fi

  echo "Tunnel attribue : $url"
  echo "Attente de l'enregistrement du connecteur Cloudflare..."
  if ! wait_for_tunnel_registered; then
    echo "Erreur: cloudflared n'a pas enregistre de connexion au reseau Cloudflare." >&2
    echo "Le processus n'est pas tue automatiquement: cloudflared sait gerer ses reconnexions." >&2
    tail -n 35 "$TUNNEL_LOG" >&2 || true
    return 1
  fi

  TUNNEL_URL="$url"
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

  if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1 || true
  fi

  if is_running "$SERVER_PID_FILE"; then
    echo "Serveur deja actif (PID $(read_pid "$SERVER_PID_FILE"))."
  else
    : > "$SERVER_LOG"
    echo "Demarrage du serveur sur $ORIGIN..."
    nohup env PORT="$PORT" node "$SERVER_ENTRY" </dev/null >>"$SERVER_LOG" 2>&1 &
    echo "$!" > "$SERVER_PID_FILE"
  fi

  if ! wait_for_health; then
    echo "Erreur: le serveur ne repond pas sur /health." >&2
    tail -n 30 "$SERVER_LOG" >&2 || true
    exit 1
  fi

  if ! get_or_start_tunnel; then
    echo "Le serveur local reste actif sur $ORIGIN." >&2
    exit 1
  fi

  local url="$TUNNEL_URL"
  local public_state="en propagation / diagnostic local non concluant"
  if wait_for_public_health_soft "$url"; then
    public_state="OK"
  fi

  echo
  echo "Serveur pret. Connecteur Cloudflare enregistre."
  echo "URL publique : $url"
  echo "URL locale   : $ORIGIN"
  echo "Health public: $public_state"

  if [[ "$public_state" != "OK" ]]; then
    echo "Note: le test HTTP depuis ce telephone n'a pas encore repondu." >&2
    echo "Le tunnel reste lance; Cloudflare indique qu'un Quick Tunnel peut prendre un peu de temps a devenir joignable." >&2
  fi

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
  local connector_state="non enregistre"
  local health_state="indisponible"
  local public_state="indisponible"

  if is_running "$SERVER_PID_FILE"; then
    node_state="actif (PID $(read_pid "$SERVER_PID_FILE"))"
  fi
  if is_running "$TUNNEL_PID_FILE"; then
    tunnel_state="actif (PID $(read_pid "$TUNNEL_PID_FILE"))"
  fi
  if tunnel_registered; then
    connector_state="enregistre"
  fi
  if curl --silent --fail --connect-timeout 2 --max-time 3 "$ORIGIN/health" >/dev/null 2>&1; then
    health_state="OK"
  fi

  local url
  url="$(find_tunnel_url || true)"
  if [[ -n "$url" ]] && public_health_ok "$url"; then
    public_state="OK"
  elif [[ -n "$url" ]] && tunnel_registered; then
    public_state="en propagation / probe local en echec"
  fi

  echo "Node          : $node_state"
  echo "cloudflared   : $tunnel_state"
  echo "Connecteur CF : $connector_state"
  echo "Health local  : $health_state"
  [[ -n "$url" ]] && echo "URL           : $url"
  [[ -n "$url" ]] && echo "Health public : $public_state"
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
  if ! tunnel_registered; then
    echo "Le connecteur cloudflared n'est pas encore enregistre." >&2
    echo "Diagnostic: bash scripts/termux-server.sh doctor" >&2
    exit 1
  fi
  open_public_url "$url"
}

doctor() {
  status_server
  echo
  echo "cloudflared : $(cloudflared --version 2>/dev/null || echo 'indisponible')"
  local config_path
  config_path="$(quick_tunnel_config_path || true)"
  if [[ -n "$config_path" ]]; then
    echo "Config Quick Tunnel incompatible detectee: $config_path"
  else
    echo "Config Quick Tunnel: OK (aucun config.yml/config.yaml detecte)"
  fi
  echo
  echo "--- Dernieres lignes serveur ---"
  tail -n 25 "$SERVER_LOG" 2>/dev/null || true
  echo
  echo "--- Dernieres lignes cloudflared ---"
  tail -n 45 "$TUNNEL_LOG" 2>/dev/null || true
  echo
  if command -v termux-wake-lock >/dev/null 2>&1; then
    echo "Wake-lock     : commande disponible"
  else
    echo "Wake-lock     : commande absente"
  fi
  echo "Un probe HTTP public en echec n'arrete jamais automatiquement un connecteur Cloudflare enregistre."
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
  start    demarre Node + un Quick Tunnel et attend l'enregistrement Cloudflare
  stop     arrete le tunnel et le serveur
  restart  redemarre les deux processus et rouvre le navigateur
  status   affiche PID, enregistrement Cloudflare et healthchecks
  doctor   affiche etat, version/config et derniers logs Node/cloudflared
  logs     suit les logs Node + cloudflared
  url      affiche uniquement l'URL trycloudflare.com
  open     ouvre l'URL du tunnel enregistre dans Chrome / navigateur Android
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
