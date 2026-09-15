#!/usr/bin/env bash
# Sandbox-safe Quick Tunnel readiness helpers.
# This file is meant to be sourced.
#
# Important: do not use the Termux/Android system resolver here. Some Termux
# runtimes and language stacks have resolver behavior that differs from Chrome.
# We query Cloudflare DNS over HTTPS through a literal IP and then use curl
# --resolve to test the public HTTPS route without any local DNS lookup.

CLOUDFLARE_DOH_HOST="cloudflare-dns.com"
CLOUDFLARE_DOH_IP_PRIMARY="1.1.1.1"
CLOUDFLARE_DOH_IP_SECONDARY="1.0.0.1"

cloudflare_doh_json() {
  local host="$1"
  local resolver_ip

  for resolver_ip in "$CLOUDFLARE_DOH_IP_PRIMARY" "$CLOUDFLARE_DOH_IP_SECONDARY"; do
    if curl --silent --show-error --fail \
      --resolve "$CLOUDFLARE_DOH_HOST:443:$resolver_ip" \
      --connect-timeout 3 --max-time 8 \
      --header 'accept: application/dns-json' \
      "https://$CLOUDFLARE_DOH_HOST/dns-query?name=$host&type=A"; then
      return 0
    fi
  done

  return 1
}

cloudflare_doh_lookup_a() {
  local host="$1"
  local json
  json="$(cloudflare_doh_json "$host" 2>/dev/null)" || return 1

  printf '%s' "$json" | node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => input += chunk);
    process.stdin.on("end", () => {
      try {
        const payload = JSON.parse(input);
        if (payload.Status !== 0) process.exit(1);
        const addresses = (payload.Answer ?? [])
          .filter((answer) => answer.type === 1 && typeof answer.data === "string")
          .map((answer) => answer.data)
          .filter((value) => /^\d{1,3}(?:\.\d{1,3}){3}$/.test(value));
        if (!addresses.length) process.exit(1);
        process.stdout.write([...new Set(addresses)].join("\n"));
      } catch {
        process.exit(1);
      }
    });
  '
}

public_health_via_ip() {
  local url="$1"
  local ip="$2"
  local host="${url#https://}"
  host="${host%%/*}"

  curl --silent --show-error --fail --location \
    --resolve "$host:443:$ip" \
    --connect-timeout 3 --max-time 8 \
    "$url/health" 2>/dev/null | grep -q '"ok"[[:space:]]*:[[:space:]]*true'
}

quick_tunnel_public_health() {
  local url="$1"
  local host="${url#https://}"
  host="${host%%/*}"
  local addresses ip

  addresses="$(cloudflare_doh_lookup_a "$host" 2>/dev/null)" || return 1
  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    if public_health_via_ip "$url" "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  done <<< "$addresses"

  return 1
}

wait_for_quick_tunnel_public_ready() {
  local url="$1"
  local max_seconds="${2:-120}"
  local log_prefix="${3:-READY}"
  local host="${url#https://}"
  host="${host%%/*}"
  local elapsed=0 addresses="" healthy_ip=""

  while (( elapsed <= max_seconds )); do
    addresses="$(cloudflare_doh_lookup_a "$host" 2>/dev/null || true)"
    if [[ -n "$addresses" ]]; then
      while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        if public_health_via_ip "$url" "$ip"; then
          healthy_ip="$ip"
          printf '[%s] public route ready host=%s edge_ip=%s after=%ss\n' \
            "$log_prefix" "$host" "$healthy_ip" "$elapsed"
          return 0
        fi
      done <<< "$addresses"
    fi

    if (( elapsed % 10 == 0 )); then
      if [[ -n "$addresses" ]]; then
        printf '[%s] DNS published but /health not ready host=%s addresses=%q elapsed=%ss\n' \
          "$log_prefix" "$host" "$addresses" "$elapsed"
      else
        printf '[%s] waiting Cloudflare DoH publication host=%s elapsed=%ss\n' \
          "$log_prefix" "$host" "$elapsed"
      fi
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}
