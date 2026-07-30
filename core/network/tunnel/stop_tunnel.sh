#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${CORE_DIR}/logging/log.sh"
# shellcheck disable=SC1091
source "${CORE_DIR}/config/load_config.sh"

CORE_CONFIG_FILE="${CORE_CONFIG_FILE:-/root/.env}"
if [ -f "$CORE_CONFIG_FILE" ]; then
  core_load_config "$CORE_CONFIG_FILE"
fi

CF_CONFIG_DIR="${CF_CONFIG_DIR:-${HOME}/.cloudflared}"
CF_CONFIG_FILE="${CF_CONFIG_FILE:-${CF_CONFIG_DIR}/config.yml}"
PROCESS_PATTERN="cloudflared.*--config ${CF_CONFIG_FILE}.*run"

if ! pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_info "Tunnel is not running for config: $CF_CONFIG_FILE"
  exit 0
fi

core_info "Stopping tunnel for config: $CF_CONFIG_FILE"
pkill -f "$PROCESS_PATTERN" 2>/dev/null || true
sleep 2

if pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_error "Tunnel is still running."
  pgrep -af "$PROCESS_PATTERN" || true
  exit 1
fi

core_ok "Tunnel stopped."
