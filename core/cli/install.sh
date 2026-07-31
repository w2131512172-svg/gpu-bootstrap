#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_SOURCE="${SCRIPT_DIR}/everspark"
CLI_TARGET="${EVERSPARK_CLI_PATH:-/usr/local/bin/everspark}"

if [ "${EUID}" -ne 0 ]; then
  echo "[ERROR] EverSpark CLI installation requires root." >&2
  exit 1
fi

if [ ! -f "$CLI_SOURCE" ]; then
  echo "[ERROR] EverSpark CLI source not found: $CLI_SOURCE" >&2
  exit 1
fi

chmod +x "$CLI_SOURCE"
install -d "$(dirname "$CLI_TARGET")"
ln -sfn "$CLI_SOURCE" "$CLI_TARGET"

echo "[OK] EverSpark CLI installed: $CLI_TARGET -> $CLI_SOURCE"
