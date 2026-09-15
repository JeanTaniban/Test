#!/usr/bin/env bash
set -u

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="${STATE_DIR:-$ROOT_DIR/.termux-golf}"
PORT="${PORT:-3000}"
ORIGIN="${ORIGIN:-http://127.0.0.1:$PORT}"
SERVER_PID_FILE="$STATE_DIR/server.pid"
TUNNEL_PID_FILE="$STATE_DIR/tunnel.pid"

mkdir -p "$STATE_DIR"

now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

read_pid() {
  local file="$1"
  [[ -f "$file" ]] && cat "$file" 2>/dev/null || true
}

process_state() {
  local file="$1"
  local pid
  pid="$(read_pid "$file")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    printf 'up:%s' "$pid"
  elif [[ -n "$pid" ]]; then
    printf 'down:%s' "$pid"
  else
    printf 'down:none'
  fi
}

health_state() {
  if curl --silent --fail --connect-timeout 1 --max-time 2 "$ORIGIN/health" >/dev/null 2>&1; then
    printf 'ok'
  else
    printf 'fail'
  fi
}

log_line() {
  printf '[%s] %s\n' "$(now)" "$*"
}

on_exit() {
  local code=$?
  log_line "watchdog exit code=$code pid=$$"
}
trap on_exit EXIT
trap 'log_line "watchdog received SIGTERM"; exit 0' TERM
trap 'log_line "watchdog received SIGINT"; exit 0' INT

log_line "watchdog started pid=$$ origin=$ORIGIN"

previous=""
iteration=0
while true; do
  node_state="$(process_state "$SERVER_PID_FILE")"
  tunnel_state="$(process_state "$TUNNEL_PID_FILE")"
  local_health="$(health_state)"
  current="node=$node_state cloudflared=$tunnel_state health=$local_health"

  if [[ "$current" != "$previous" ]]; then
    log_line "state-change $current"
    previous="$current"
  fi

  if (( iteration % 15 == 0 )); then
    log_line "heartbeat $current"
  fi

  iteration=$((iteration + 1))
  sleep 2
done
