#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

export CORE_CONFIG_FILE="${CORE_CONFIG_FILE:-/root/.env.webui}"

exec bash "${REPO_ROOT}/core/network/tunnel/stop_tunnel.sh" "$@"
