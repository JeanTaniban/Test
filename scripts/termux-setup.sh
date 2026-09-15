#!/usr/bin/env bash
set -euo pipefail

if [[ "${PREFIX:-}" != *"com.termux"* ]]; then
  echo "Erreur: ce script doit etre execute dans Termux sur Android." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Mise a jour de l'index des paquets Termux..."
pkg update -y

echo "[2/4] Installation des outils..."
pkg install -y git curl cloudflared
if ! command -v node >/dev/null 2>&1; then
  pkg install -y nodejs-lts || pkg install -y nodejs
fi

for command_name in node npm git curl cloudflared; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Erreur: $command_name n'est pas disponible apres installation." >&2
    exit 1
  fi
done

echo "[3/4] Installation des dependances Node..."
npm install --no-audit --no-fund

echo "[4/4] Tests de type et build..."
npm run typecheck
npm run build:client
npm run build:server

mkdir -p .termux-golf

echo
echo "Termux est pret."
echo "Demarrage : bash scripts/termux-server.sh start"
echo "Etat      : bash scripts/termux-server.sh status"
echo "URL       : bash scripts/termux-server.sh url"
echo "Arret     : bash scripts/termux-server.sh stop"
