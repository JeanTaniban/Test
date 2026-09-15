#!/usr/bin/env bash
# Helpers shared by the Termux launch/debug scripts.
# This file is meant to be sourced.

system_dns_lookup() {
  local host="$1"
  node -e '
    const dns = require("node:dns");
    const host = process.argv[1];
    dns.lookup(host, { all: true }, (error, addresses) => {
      if (error) {
        console.error(`${error.code ?? "DNS_ERROR"}: ${error.message}`);
        process.exit(1);
      }
      if (!addresses.length) process.exit(1);
      console.log(addresses.map((entry) => entry.address).join(","));
    });
  ' "$host"
}

public_health_via_system_dns() {
  local url="$1"
  curl --silent --show-error --fail --location \
    --connect-timeout 3 --max-time 6 \
    "$url/health" 2>/dev/null | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

public_health_via_cloudflare_doh() {
  local url="$1"
  curl --silent --show-error --fail --location \
    --doh-url https://1.1.1.1/dns-query \
    --connect-timeout 3 --max-time 8 \
    "$url/health" 2>/dev/null | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

cloudflare_doh_supported() {
  curl --help all 2>/dev/null | grep -q -- '--doh-url'
}

wait_for_quick_tunnel_dns() {
  local url="$1"
  local max_seconds="${2:-120}"
  local log_prefix="${3:-DNS}"
  local host="${url#https://}"
  host="${host%%/*}"
  local elapsed=0
  local system_result=""
  local doh_state="unknown"

  while (( elapsed <= max_seconds )); do
    if system_result="$(system_dns_lookup "$host" 2>&1)"; then
      printf '[%s] system DNS resolved host=%s addresses=%s after=%ss\n' "$log_prefix" "$host" "$system_result" "$elapsed"
      return 0
    fi

    if (( elapsed % 10 == 0 )); then
      doh_state="unsupported"
      if cloudflare_doh_supported; then
        if public_health_via_cloudflare_doh "$url"; then
          doh_state="published-and-origin-healthy"
        else
          doh_state="not-ready-or-unreachable"
        fi
      fi
      printf '[%s] waiting DNS host=%s elapsed=%ss system=%q cloudflare_doh=%s\n' \
        "$log_prefix" "$host" "$elapsed" "${system_result:-no-answer}" "$doh_state"
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}
