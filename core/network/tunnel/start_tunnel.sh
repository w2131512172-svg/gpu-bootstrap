#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${CORE_DIR}/logging/log.sh"
# shellcheck disable=SC1091
source "${CORE_DIR}/utils/common.sh"
# shellcheck disable=SC1091
source "${CORE_DIR}/config/load_config.sh"
# shellcheck disable=SC1091
source "${CORE_DIR}/network/cloudflared.sh"

CORE_CONFIG_FILE="${CORE_CONFIG_FILE:-/root/.env}"
if [ -f "$CORE_CONFIG_FILE" ]; then
  core_load_config "$CORE_CONFIG_FILE"
fi

core_config_require CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT
core_cloudflared_require

CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-${CF_HOSTNAME}}"
CF_CONFIG_DIR="${CF_CONFIG_DIR:-${HOME}/.cloudflared}"
CF_CONFIG_FILE="${CF_CONFIG_FILE:-${CF_CONFIG_DIR}/config.yml}"
CF_CREDENTIAL_SOURCE="${CF_CREDENTIAL_SOURCE:-${HOME}/${CF_TUNNEL_UUID}.json}"
CF_CREDENTIAL_FILE="${CF_CREDENTIAL_FILE:-${CF_CONFIG_DIR}/${CF_TUNNEL_UUID}.json}"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-${LOG_DIR}/cloudflared.log}"
CORE_LOG_FILE="${TUNNEL_START_LOG:-${LOG_DIR}/tunnel_start.log}"
export CORE_LOG_FILE

core_ensure_dir "$LOG_DIR"
core_ensure_dir "$CF_CONFIG_DIR"

if [ ! -f "$CF_CREDENTIAL_FILE" ]; then
  core_require_file "$CF_CREDENTIAL_SOURCE" \
    "Upload the tunnel credential or set CF_CREDENTIAL_SOURCE."
  cp "$CF_CREDENTIAL_SOURCE" "$CF_CREDENTIAL_FILE"
  core_ok "Tunnel credential installed: $CF_CREDENTIAL_FILE"
fi
chmod 600 "$CF_CREDENTIAL_FILE"

export CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT
export CF_CONFIG_DIR CF_CONFIG_FILE CF_CREDENTIAL_FILE

bash "${SCRIPT_DIR}/render_tunnel_config.sh"

PROCESS_PATTERN="cloudflared.*--config ${CF_CONFIG_FILE}.*run"
if pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_info "Stopping existing tunnel process for config: $CF_CONFIG_FILE"
  pkill -f "$PROCESS_PATTERN" 2>/dev/null || true
  sleep 2
fi

core_info "Starting tunnel: $CF_TUNNEL_NAME"
nohup cloudflared tunnel --config "$CF_CONFIG_FILE" run \
  > "$CLOUDFLARED_LOG" 2>&1 &

sleep 3

if ! pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_error "Tunnel process failed."
  tail -n 80 "$CLOUDFLARED_LOG" || true
  exit 1
fi

if grep -q "Registered tunnel connection" "$CLOUDFLARED_LOG"; then
  core_ok "Tunnel registered with Cloudflare."
else
  core_warn "Tunnel is running, but registration is not visible in the log yet."
fi

core_info "Hostname: https://${CF_HOSTNAME}"
core_info "Local service: http://127.0.0.1:${CF_LOCAL_PORT}"
core_info "cloudflared log: $CLOUDFLARED_LOG"
