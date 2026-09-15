#!/usr/bin/env bash
set -u

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/.termux-golf}"
PORT="${PORT:-3000}"
ORIGIN="${ORIGIN:-http://127.0.0.1:$PORT}"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog.pid"
SERVER_LOG="$STATE_DIR/server.log"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
WATCHDOG_LOG="$STATE_DIR/watchdog.log"
SUPERVISOR_LOG="$STATE_DIR/supervisor.log"

mkdir -p "$STATE_DIR"
REPORT="$STATE_DIR/diagnostic-$(date '+%Y%m%d-%H%M%S').txt"

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  printf '$ %s\n' "$*"
  "$@" 2>&1 || printf '[exit=%s]\n' "$?"
}

read_pid() {
  local file="$1"
  [[ -f "$file" ]] && cat "$file" 2>/dev/null || true
}

find_tunnel_url() {
  [[ -f "$TUNNEL_LOG" ]] || return 1
  grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1
}

process_report() {
  local label="$1"
  local file="$2"
  local pid
  pid="$(read_pid "$file")"

  printf '%s pid-file: %s\n' "$label" "${pid:-absent}"
  if [[ -z "$pid" ]]; then
    return
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    printf '%s process: NOT RUNNING\n' "$label"
    return
  fi

  printf '%s process: RUNNING\n' "$label"
  if command -v ps >/dev/null 2>&1; then
    ps -o PID,PPID,STAT,ELAPSED,RSS,ARGS -p "$pid" 2>&1 || ps -p "$pid" 2>&1 || true
  fi
  if [[ -r "/proc/$pid/cmdline" ]]; then
    printf 'cmdline: '
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true
    printf '\n'
  fi
  if [[ -r "/proc/$pid/status" ]]; then
    grep -E '^(Name|State|Pid|PPid|Threads|VmRSS|VmSize|VmPeak|SigQ|SigPnd|ShdPnd):' "/proc/$pid/status" 2>/dev/null || true
  fi
  [[ -r "/proc/$pid/oom_score" ]] && printf 'oom_score: %s\n' "$(cat "/proc/$pid/oom_score" 2>/dev/null || true)"
  [[ -r "/proc/$pid/oom_score_adj" ]] && printf 'oom_score_adj: %s\n' "$(cat "/proc/$pid/oom_score_adj" 2>/dev/null || true)"
}

curl_probe() {
  local label="$1"
  local url="$2"
  local body="$STATE_DIR/.diag-body.$$"
  printf '\n-- %s: %s --\n' "$label" "$url"
  curl --show-error --location \
    --connect-timeout 5 --max-time 12 \
    --dump-header - --output "$body" \
    --write-out '\n[curl] http_code=%{http_code} remote_ip=%{remote_ip} remote_port=%{remote_port} local_ip=%{local_ip} namelookup=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s starttransfer=%{time_starttransfer}s total=%{time_total}s\n' \
    "$url" 2>&1 || printf '[curl exit=%s]\n' "$?"
  if [[ -f "$body" ]]; then
    printf '%s\n' '-- body (first 1000 bytes) --'
    head -c 1000 "$body" 2>/dev/null || true
    printf '\n'
    rm -f "$body"
  fi
}

{
  printf 'MULTIPLAYER GOLF - TERMUX DIAGNOSTIC\n'
  printf 'Generated: %s\n' "$(date -Iseconds 2>/dev/null || date)"
  printf 'Report: %s\n' "$REPORT"

  section 'Repository'
  (cd "$ROOT_DIR" && run git rev-parse HEAD)
  (cd "$ROOT_DIR" && run git status --short)
  (cd "$ROOT_DIR" && run git branch --show-current)

  section 'System'
  run uname -a
  run uptime
  command -v getprop >/dev/null 2>&1 && {
    printf 'manufacturer: %s\n' "$(getprop ro.product.manufacturer 2>/dev/null || true)"
    printf 'model: %s\n' "$(getprop ro.product.model 2>/dev/null || true)"
    printf 'android_release: %s\n' "$(getprop ro.build.version.release 2>/dev/null || true)"
    printf 'android_sdk: %s\n' "$(getprop ro.build.version.sdk 2>/dev/null || true)"
  }
  printf 'PREFIX: %s\n' "${PREFIX:-unset}"
  printf 'HOME: %s\n' "${HOME:-unset}"

  section 'Tool versions'
  run node --version
  run npm --version
  run cloudflared --version
  run curl --version
  if command -v termux-info >/dev/null 2>&1; then
    run termux-info
  else
    printf 'termux-info: unavailable\n'
  fi

  section 'Managed process state'
  process_report 'Node' "$SERVER_PID_FILE"
  printf '\n'
  process_report 'cloudflared' "$TUNNEL_PID_FILE"
  printf '\n'
  process_report 'watchdog' "$WATCHDOG_PID_FILE"

  section 'Matching processes'
  if command -v ps >/dev/null 2>&1; then
    ps -A -o PID,PPID,STAT,ELAPSED,RSS,ARGS 2>&1 | grep -E '(^ *PID|node|cloudflared|termux-watchdog|termux-supervise)' || true
  fi

  section 'Local health probe'
  curl_probe 'local /health' "$ORIGIN/health"

  url="$(find_tunnel_url || true)"
  if [[ -n "$url" ]]; then
    host="${url#https://}"
    host="${host%%/*}"
    section 'Cloudflare URL and DNS'
    printf 'url: %s\n' "$url"
    printf 'host: %s\n' "$host"
    node -e "require('dns').lookup(process.argv[1], {all:true}, (e,a)=>{if(e){console.error(e);process.exitCode=1}else console.log(JSON.stringify(a,null,2))})" "$host" 2>&1 || true

    section 'Public health probes'
    curl_probe 'public default' "$url/health"
    printf '\n-- public HTTP/1.1 --\n'
    curl --http1.1 --show-error --location --connect-timeout 5 --max-time 12 \
      --output /dev/null --write-out '[curl-h1] code=%{http_code} remote_ip=%{remote_ip} total=%{time_total}s\n' \
      "$url/health" 2>&1 || printf '[curl-h1 exit=%s]\n' "$?"
    printf '\n-- public IPv4 --\n'
    curl -4 --show-error --location --connect-timeout 5 --max-time 12 \
      --output /dev/null --write-out '[curl-v4] code=%{http_code} remote_ip=%{remote_ip} total=%{time_total}s\n' \
      "$url/health" 2>&1 || printf '[curl-v4 exit=%s]\n' "$?"
  else
    section 'Cloudflare URL'
    printf 'No trycloudflare.com URL found in tunnel log.\n'
  fi

  section 'Quick Tunnel configuration'
  for path in "$HOME/.cloudflared/config.yml" "$HOME/.cloudflared/config.yaml"; do
    if [[ -f "$path" ]]; then
      printf 'FOUND incompatible Quick Tunnel config: %s\n' "$path"
    else
      printf 'absent: %s\n' "$path"
    fi
  done

  section 'Android background hints'
  printf 'termux-wake-lock command: '
  command -v termux-wake-lock >/dev/null 2>&1 && printf 'available\n' || printf 'unavailable\n'
  if command -v settings >/dev/null 2>&1; then
    printf 'global low_power: %s\n' "$(settings get global low_power 2>&1 || true)"
  fi
  if command -v am >/dev/null 2>&1; then
    printf 'am get-inactive com.termux: '
    am get-inactive com.termux 2>&1 || true
  fi

  section 'Foreground supervisor trace'
  tail -n 260 "$SUPERVISOR_LOG" 2>/dev/null || printf 'supervisor.log unavailable (run scripts/termux-debug.sh)\n'

  section 'Server log tail'
  tail -n 220 "$SERVER_LOG" 2>/dev/null || printf 'server.log unavailable\n'

  section 'cloudflared log tail'
  tail -n 240 "$TUNNEL_LOG" 2>/dev/null || printf 'tunnel.log unavailable\n'

  section 'Watchdog log tail'
  tail -n 180 "$WATCHDOG_LOG" 2>/dev/null || printf 'watchdog.log unavailable\n'

  section 'End'
  printf 'Send this complete report for diagnosis.\n'
} | tee "$REPORT"

printf '\nDiagnostic report saved to: %s\n' "$REPORT"
