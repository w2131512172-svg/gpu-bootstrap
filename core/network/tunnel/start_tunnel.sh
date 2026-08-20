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
  set -a
  # shellcheck disable=SC1090
  source "$CORE_CONFIG_FILE"
  set +a
fi

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
TUNNEL_LOG="${TUNNEL_LOG:-${LOG_DIR}/tunnel.log}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-${LOG_DIR}/cloudflared.log}"
core_log_init tunnel.lifecycle "$TUNNEL_LOG"

core_config_require CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT
core_cloudflared_require

CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-${CF_HOSTNAME}}"
CF_CONFIG_DIR="${CF_CONFIG_DIR:-${HOME}/.cloudflared}"
CF_CONFIG_FILE="${CF_CONFIG_FILE:-${CF_CONFIG_DIR}/config.yml}"
CF_CREDENTIAL_SOURCE="${CF_CREDENTIAL_SOURCE:-${HOME}/${CF_TUNNEL_UUID}.json}"
CF_CREDENTIAL_FILE="${CF_CREDENTIAL_FILE:-${CF_CONFIG_DIR}/${CF_TUNNEL_UUID}.json}"

core_ensure_dir "$CF_CONFIG_DIR"

if [ ! -f "$CF_CREDENTIAL_FILE" ]; then
  core_require_file "$CF_CREDENTIAL_SOURCE" \
    "Upload the tunnel credential or set CF_CREDENTIAL_SOURCE."
  cp "$CF_CREDENTIAL_SOURCE" "$CF_CREDENTIAL_FILE"
  core_ok tunnel.credential.ready "Tunnel credential installed"
fi
chmod 600 "$CF_CREDENTIAL_FILE"

export CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT
export CF_CONFIG_DIR CF_CONFIG_FILE CF_CREDENTIAL_FILE

bash "${SCRIPT_DIR}/render_tunnel_config.sh"

PROCESS_PATTERN="cloudflared.*--config ${CF_CONFIG_FILE}.*run"
if pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_info tunnel.restart "Stopping the existing tunnel process"
  pkill -f "$PROCESS_PATTERN" 2>/dev/null || true
  sleep 2
fi

core_info tunnel.start "Starting Cloudflare tunnel" \
  "name=$CF_TUNNEL_NAME" "hostname=$CF_HOSTNAME" "local_port=$CF_LOCAL_PORT"
nohup cloudflared tunnel --config "$CF_CONFIG_FILE" run \
  > "$CLOUDFLARED_LOG" 2>&1 &
TUNNEL_PID=$!

sleep 3

if ! pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_error tunnel.start.failed "Tunnel process failed" \
    "pid=$TUNNEL_PID" "cloudflared_log=$CLOUDFLARED_LOG"
  tail -n 80 "$CLOUDFLARED_LOG" >&2 || true
  exit 1
fi

if grep -q "Registered tunnel connection" "$CLOUDFLARED_LOG"; then
  core_ok tunnel.registered "Tunnel registered with Cloudflare" "pid=$TUNNEL_PID"
else
  core_warn tunnel.registration.pending "Tunnel is running but registration is not visible yet" \
    "pid=$TUNNEL_PID"
fi

core_ok tunnel.ready "Tunnel lifecycle startup completed" \
  "url=https://${CF_HOSTNAME}" "local_url=http://127.0.0.1:${CF_LOCAL_PORT}" \
  "cloudflared_log=$CLOUDFLARED_LOG"
