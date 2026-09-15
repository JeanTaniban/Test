#!/usr/bin/env bash
set -u

ROOT_DIR="${ROOT_DIR:?ROOT_DIR required}"
STATE_DIR="${STATE_DIR:?STATE_DIR required}"
PORT="${PORT:-3000}"
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-1}"
DNS_WAIT_SECONDS="${DNS_WAIT_SECONDS:-120}"
ORIGIN="http://127.0.0.1:$PORT"
SERVER_ENTRY="$ROOT_DIR/dist/server/apps/server/src/index.js"
SUPERVISOR_LOG="$STATE_DIR/supervisor.log"
SERVER_LOG="$STATE_DIR/server.log"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"
DNS_HELPER="$ROOT_DIR/scripts/termux-dns.sh"
NEW_LINE_COUNT=0

mkdir -p "$STATE_DIR"
source "$DNS_HELPER"

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

open_url() {
  local url="$1"
  log "opening browser url=$url"
  if command -v am >/dev/null 2>&1 && am start -a android.intent.action.VIEW -d "$url" -p com.android.chrome >/dev/null 2>&1; then
    log "browser launch=chrome-intent OK"
    return 0
  fi
  if command -v termux-open-url >/dev/null 2>&1 && termux-open-url "$url" >/dev/null 2>&1; then
    log "browser launch=termux-open-url OK"
    return 0
  fi
  if command -v am >/dev/null 2>&1 && am start -a android.intent.action.VIEW -d "$url" >/dev/null 2>&1; then
    log "browser launch=generic-intent OK"
    return 0
  fi
  log "browser launch FAILED; open manually: $url"
}

print_new_lines() {
  local file="$1"
  local prefix="$2"
  local previous="$3"
  local current
  current="$(wc -l < "$file" 2>/dev/null || echo 0)"
  if (( current > previous )); then
    sed -n "$((previous + 1)),${current}p" "$file" | sed "s/^/[$prefix] /" | tee -a "$SUPERVISOR_LOG"
  fi
  NEW_LINE_COUNT="$current"
}

proc_summary() {
  local label="$1"
  local pid="$2"
  if [[ ! -r "/proc/$pid/status" ]]; then
    printf '%s=missing' "$label"
    return
  fi
  local state rss threads oom
  state="$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null || echo '?')"
  rss="$(awk '/^VmRSS:/ {print $2 $3}' "/proc/$pid/status" 2>/dev/null || echo '?')"
  threads="$(awk '/^Threads:/ {print $2}' "/proc/$pid/status" 2>/dev/null || echo '?')"
  oom="$(cat "/proc/$pid/oom_score" 2>/dev/null || echo '?')"
  printf '%s=pid:%s,state:%s,rss:%s,threads:%s,oom:%s' "$label" "$pid" "$state" "$rss" "$threads" "$oom"
}

wait_public_health() {
  local url="$1"
  local elapsed=0
  while (( elapsed <= 60 )); do
    if public_health_via_system_dns "$url"; then
      log "public health OK after=${elapsed}s url=$url"
      return 0
    fi
    if ! kill -0 "$server_pid" 2>/dev/null || ! kill -0 "$tunnel_pid" 2>/dev/null; then
      return 1
    fi
    if (( elapsed % 10 == 0 )); then
      log "waiting public HTTP health elapsed=${elapsed}s"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

: > "$SUPERVISOR_LOG"
: > "$SERVER_LOG"
: > "$TUNNEL_LOG"

log "supervisor start shell_pid=$$ port=$PORT cwd=$ROOT_DIR"
log "node=$(node --version 2>/dev/null || echo unavailable) cloudflared=$(cloudflared --version 2>/dev/null || echo unavailable)"
if command -v settings >/dev/null 2>&1; then
  private_dns_mode="$(settings get global private_dns_mode 2>/dev/null || true)"
  private_dns_specifier="$(settings get global private_dns_specifier 2>/dev/null || true)"
  log "android private_dns_mode=${private_dns_mode:-unknown} private_dns_specifier=${private_dns_specifier:-none}"
fi

cd "$ROOT_DIR" || exit 1

env PORT="$PORT" SERVER_DIAGNOSTICS=1 node "$SERVER_ENTRY" >>"$SERVER_LOG" 2>&1 &
server_pid=$!
printf '%s\n' "$server_pid" > "$SERVER_PID_FILE"
log "node started pid=$server_pid entry=$SERVER_ENTRY"

local_health_ok=0
for _ in $(seq 1 30); do
  if curl --silent --fail --connect-timeout 1 --max-time 2 "$ORIGIN/health" >/dev/null 2>&1; then
    local_health_ok=1
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
if (( local_health_ok == 0 )); then
  log "ERROR local health never became ready"
  tail -n 80 "$SERVER_LOG" | sed 's/^/[server] /' | tee -a "$SUPERVISOR_LOG"
  cleanup EXIT
  exit 1
fi

cloudflared tunnel --url "$ORIGIN" >>"$TUNNEL_LOG" 2>&1 &
tunnel_pid=$!
printf '%s\n' "$tunnel_pid" > "$TUNNEL_PID_FILE"
log "cloudflared started pid=$tunnel_pid"

url=""
registered=0
for _ in $(seq 1 90); do
  url="$(grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
  if [[ -n "$url" ]] && grep -q 'Registered tunnel connection' "$TUNNEL_LOG"; then
    registered=1
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

if (( registered == 0 )) || [[ -z "$url" ]]; then
  log "ERROR Quick Tunnel never reached registered state url=${url:-none}"
  tail -n 120 "$TUNNEL_LOG" | sed 's/^/[cloudflared] /' | tee -a "$SUPERVISOR_LOG"
  cleanup EXIT
  exit 1
fi

printf '%s\n' "$url" > "$STATE_DIR/current-url"
log "connector READY url=$url"

last_server_lines=0
last_tunnel_lines=0
print_new_lines "$SERVER_LOG" server "$last_server_lines"; last_server_lines="$NEW_LINE_COUNT"
print_new_lines "$TUNNEL_LOG" cloudflared "$last_tunnel_lines"; last_tunnel_lines="$NEW_LINE_COUNT"

echo
printf '=== DNS READINESS ===\n'
printf 'URL attribuee: %s\n' "$url"
printf 'Cloudflare est connecte; attente de la publication/resolution DNS avant Chrome.\n\n'

if wait_for_quick_tunnel_dns "$url" "$DNS_WAIT_SECONDS" dns > >(tee -a "$SUPERVISOR_LOG") 2>&1; then
  log "system DNS READY url=$url"
else
  log "ERROR system DNS unresolved after ${DNS_WAIT_SECONDS}s url=$url"
  if cloudflare_doh_supported && public_health_via_cloudflare_doh "$url"; then
    log "DIAG Cloudflare DoH resolves and reaches origin, but Android/system DNS does not"
    printf '\nERREUR DNS LOCALE: 1.1.1.1 voit le tunnel, mais le DNS Android/Termux ne le resout pas.\n'
    printf 'Le serveur et le tunnel restent actifs. Verifie Private DNS / DNS filtre sur Android.\n'
  else
    log "DIAG Cloudflare DoH also not ready; Quick Tunnel hostname not publicly usable yet"
    printf '\nLe hostname Quick Tunnel ne s est pas publie dans le delai de %ss.\n' "$DNS_WAIT_SECONDS"
  fi
  printf 'Chrome ne sera pas ouvert avec un hostname non resolvable.\n'
fi

dns_ready=0
if system_dns_lookup "${url#https://}" >/dev/null 2>&1; then
  dns_ready=1
fi

http_ready=0
if (( dns_ready == 1 )); then
  printf '\n=== HTTP READINESS ===\n'
  if wait_public_health "$url"; then
    http_ready=1
  else
    log "ERROR DNS resolves but public /health did not become ready"
  fi
fi

if (( dns_ready == 1 && http_ready == 1 )); then
  printf '\n=== MODE DEBUG: 60 secondes de surveillance active ===\n'
  printf 'URL utilisable: %s\n' "$url"
  if [[ "$AUTO_OPEN_BROWSER" != "0" ]]; then
    open_url "$url"
  fi
else
  printf '\n=== MODE DEBUG: surveillance sans ouverture Chrome ===\n'
fi

for second in $(seq 1 60); do
  print_new_lines "$SERVER_LOG" server "$last_server_lines"; last_server_lines="$NEW_LINE_COUNT"
  print_new_lines "$TUNNEL_LOG" cloudflared "$last_tunnel_lines"; last_tunnel_lines="$NEW_LINE_COUNT"

  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"; rc=$?
    log "FATAL node exited rc=$rc at_t=${second}s"
    tail -n 160 "$SERVER_LOG" | sed 's/^/[server-final] /' | tee -a "$SUPERVISOR_LOG"
    kill "$tunnel_pid" 2>/dev/null || true
    exit "$rc"
  fi
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then
    wait "$tunnel_pid"; rc=$?
    log "FATAL cloudflared exited rc=$rc at_t=${second}s"
    tail -n 200 "$TUNNEL_LOG" | sed 's/^/[cloudflared-final] /' | tee -a "$SUPERVISOR_LOG"
    kill "$server_pid" 2>/dev/null || true
    exit "$rc"
  fi

  if (( second % 5 == 0 )); then
    local_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$ORIGIN/health" 2>&1 || true)"
    dns_result="$(system_dns_lookup "${url#https://}" 2>&1 || true)"
    public_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$url/health" 2>&1 || true)"
    log "heartbeat t=${second}s $(proc_summary node "$server_pid") $(proc_summary cloudflared "$tunnel_pid") dns=$(printf '%q' "$dns_result") local_health=$local_code public_health=$public_code"
  fi
  sleep 1
done

log "60s observation complete; node/cloudflared still alive"
log "server log=$SERVER_LOG tunnel log=$TUNNEL_LOG supervisor log=$SUPERVISOR_LOG"
disown "$server_pid" "$tunnel_pid" 2>/dev/null || true
exit 0
