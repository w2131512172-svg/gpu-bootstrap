#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${CORE_DIR}/logging/log.sh"

CORE_CONFIG_FILE="${CORE_CONFIG_FILE:-/root/.env}"
if [ -f "$CORE_CONFIG_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$CORE_CONFIG_FILE"
  set +a
fi

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
TUNNEL_LOG="${TUNNEL_LOG:-${LOG_DIR}/tunnel.log}"
core_log_init tunnel.lifecycle "$TUNNEL_LOG"

CF_CONFIG_DIR="${CF_CONFIG_DIR:-${HOME}/.cloudflared}"
CF_CONFIG_FILE="${CF_CONFIG_FILE:-${CF_CONFIG_DIR}/config.yml}"
PROCESS_PATTERN="cloudflared.*--config ${CF_CONFIG_FILE}.*run"

if ! pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_info tunnel.already_stopped "Tunnel is not running"
  exit 0
fi

core_info tunnel.stop "Stopping tunnel"
pkill -f "$PROCESS_PATTERN" 2>/dev/null || true
sleep 2

if pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_error tunnel.stop.failed "Tunnel is still running"
  pgrep -af "$PROCESS_PATTERN" >&2 || true
  exit 1
fi

core_ok tunnel.stopped "Tunnel stopped"
