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
core_load_config "$CORE_CONFIG_FILE"
core_config_require CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT
core_cloudflared_require

CF_CONFIG_DIR="${CF_CONFIG_DIR:-${HOME}/.cloudflared}"
CF_CONFIG_FILE="${CF_CONFIG_FILE:-${CF_CONFIG_DIR}/config.yml}"
CF_CREDENTIAL_FILE="${CF_CREDENTIAL_FILE:-${CF_CONFIG_DIR}/${CF_TUNNEL_UUID}.json}"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-${LOG_DIR}/cloudflared.log}"
CORE_LOG_FILE="${TUNNEL_CHECK_LOG:-${LOG_DIR}/tunnel_check.log}"
export CORE_LOG_FILE

core_ensure_dir "$LOG_DIR"
core_require_file "$CF_CONFIG_FILE"
core_require_file "$CF_CREDENTIAL_FILE"

PROCESS_PATTERN="cloudflared.*--config ${CF_CONFIG_FILE}.*run"

core_section "EverSpark Forge tunnel check"
core_info "Hostname: $CF_HOSTNAME"
core_info "Local port: $CF_LOCAL_PORT"
core_info "Tunnel UUID: $CF_TUNNEL_UUID"

if pgrep -af "$PROCESS_PATTERN" >/dev/null 2>&1; then
  core_ok "Tunnel process is running."
else
  core_die "Tunnel process is not running for config: $CF_CONFIG_FILE"
fi

if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
  core_ok "Local service is reachable: 127.0.0.1:${CF_LOCAL_PORT}"
else
  core_warn "Local service is not reachable: 127.0.0.1:${CF_LOCAL_PORT}"
fi

if [ -f "$CLOUDFLARED_LOG" ]; then
  if grep -q "Registered tunnel connection" "$CLOUDFLARED_LOG"; then
    core_ok "Tunnel registration found in cloudflared log."
  else
    core_warn "Tunnel registration is not visible in cloudflared log."
  fi
else
  core_warn "cloudflared log not found: $CLOUDFLARED_LOG"
fi

core_ok "Tunnel check completed."
