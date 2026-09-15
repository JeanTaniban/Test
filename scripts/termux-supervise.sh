#!/usr/bin/env bash
set -u

ROOT_DIR="${ROOT_DIR:?ROOT_DIR required}"
STATE_DIR="${STATE_DIR:?STATE_DIR required}"
PORT="${PORT:-3000}"
ORIGIN="http://127.0.0.1:$PORT"
SERVER_ENTRY="$ROOT_DIR/dist/server/apps/server/src/index.js"
SUPERVISOR_LOG="$STATE_DIR/supervisor.log"
SERVER_LOG="$STATE_DIR/server.log"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"

mkdir -p "$STATE_DIR"

now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { printf '[%s] %s\n' "$(now)" "$*" | tee -a "$SUPERVISOR_LOG"; }

server_pid=""
tunnel_pid=""

cleanup() {
  local sig="${1:-EXIT}"
  log "supervisor cleanup signal=$sig server_pid=${server_pid:-none} tunnel_pid=${tunnel_pid:-none}"
  [[ -n "$tunnel_pid" ]] && kill "$tunnel_pid" 2>/dev/null || true
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
}
trap 'cleanup INT; exit 130' INT
trap 'cleanup TERM; exit 143' TERM

: > "$SUPERVISOR_LOG"
: > "$SERVER_LOG"
: > "$TUNNEL_LOG"

log "supervisor start shell_pid=$$ port=$PORT cwd=$ROOT_DIR"
log "node=$(node --version 2>/dev/null || echo unavailable) cloudflared=$(cloudflared --version 2>/dev/null || echo unavailable)"

cd "$ROOT_DIR" || exit 1

env PORT="$PORT" SERVER_DIAGNOSTICS=1 node "$SERVER_ENTRY" >>"$SERVER_LOG" 2>&1 &
server_pid=$!
printf '%s\n' "$server_pid" > "$SERVER_PID_FILE"
log "node started pid=$server_pid entry=$SERVER_ENTRY"

for _ in $(seq 1 30); do
  if curl --silent --fail --connect-timeout 1 --max-time 2 "$ORIGIN/health" >/dev/null 2>&1; then
    log "local health OK"
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"; rc=$?
    log "node exited during startup rc=$rc"
    tail -n 80 "$SERVER_LOG" | sed 's/^/[server] /' | tee -a "$SUPERVISOR_LOG"
    exit "$rc"
  fi
  sleep 0.5
done

cloudflared tunnel --url "$ORIGIN" >>"$TUNNEL_LOG" 2>&1 &
tunnel_pid=$!
printf '%s\n' "$tunnel_pid" > "$TUNNEL_PID_FILE"
log "cloudflared started pid=$tunnel_pid"

url=""
for _ in $(seq 1 60); do
  url="$(grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
  if [[ -n "$url" ]] && grep -q 'Registered tunnel connection' "$TUNNEL_LOG"; then
    log "cloudflare registered url=$url"
    break
  fi
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    wait "$tunnel_pid"; rc=$?
    log "cloudflared exited during startup rc=$rc"
    tail -n 120 "$TUNNEL_LOG" | sed 's/^/[cloudflared] /' | tee -a "$SUPERVISOR_LOG"
    cleanup EXIT
    exit "$rc"
  fi
  sleep 0.5
done

if [[ -z "$url" ]]; then
  log "ERROR no Quick Tunnel URL after registration wait"
  tail -n 120 "$TUNNEL_LOG" | sed 's/^/[cloudflared] /' | tee -a "$SUPERVISOR_LOG"
  cleanup EXIT
  exit 1
fi

printf '%s\n' "$url" > "$STATE_DIR/current-url"
log "READY url=$url"

last_server_size=0
last_tunnel_size=0
for second in $(seq 1 60); do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"; rc=$?
    log "FATAL node exited rc=$rc at_t=${second}s"
    tail -n 120 "$SERVER_LOG" | sed 's/^/[server] /' | tee -a "$SUPERVISOR_LOG"
    kill "$tunnel_pid" 2>/dev/null || true
    exit "$rc"
  fi
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    wait "$tunnel_pid"; rc=$?
    log "FATAL cloudflared exited rc=$rc at_t=${second}s"
    tail -n 160 "$TUNNEL_LOG" | sed 's/^/[cloudflared] /' | tee -a "$SUPERVISOR_LOG"
    kill "$server_pid" 2>/dev/null || true
    exit "$rc"
  fi

  if (( second % 5 == 0 )); then
    local_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$ORIGIN/health" 2>&1 || true)"
    public_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$url/health" 2>&1 || true)"
    log "heartbeat t=${second}s node=alive cloudflared=alive local_health=$local_code public_health=$public_code"
  fi
  sleep 1
done

log "60s observation complete; node/cloudflared still alive"
# Keep children alive when the supervisor exits. They have no stdin and log to files.
disown "$server_pid" "$tunnel_pid" 2>/dev/null || true
exit 0
