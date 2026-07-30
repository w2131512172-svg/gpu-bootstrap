#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FORGE_ROOT}/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${FORGE_ROOT}/config.env}"

if [ -f "$CONFIG_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi

: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:=3000}"

bash "${FORGE_ROOT}/start_all.sh"
bash "${REPO_ROOT}/core/network/tunnel/start_tunnel.sh"

echo "========================================"
echo "[SUCCESS] Ollama Forge is ONLINE"
echo "https://${CF_HOSTNAME}"
echo "========================================"
