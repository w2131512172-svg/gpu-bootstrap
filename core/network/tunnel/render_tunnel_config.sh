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

core_config_require CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT

[[ "$CF_TUNNEL_UUID" =~ ^[A-Za-z0-9-]+$ ]] \
  || core_die "Invalid CF_TUNNEL_UUID: $CF_TUNNEL_UUID"
[[ "$CF_HOSTNAME" =~ ^[A-Za-z0-9.-]+$ ]] \
  || core_die "Invalid CF_HOSTNAME: $CF_HOSTNAME"
[[ "$CF_LOCAL_PORT" =~ ^[0-9]+$ ]] \
  || core_die "Invalid CF_LOCAL_PORT: $CF_LOCAL_PORT"

CF_CONFIG_DIR="${CF_CONFIG_DIR:-${HOME}/.cloudflared}"
CF_CONFIG_FILE="${CF_CONFIG_FILE:-${CF_CONFIG_DIR}/config.yml}"
CF_CREDENTIAL_FILE="${CF_CREDENTIAL_FILE:-${CF_CONFIG_DIR}/${CF_TUNNEL_UUID}.json}"
CF_TEMPLATE_FILE="${CF_TEMPLATE_FILE:-${SCRIPT_DIR}/config.template.yml}"

core_require_file "$CF_TEMPLATE_FILE"
core_ensure_dir "$CF_CONFIG_DIR"

sed \
  -e "s#__CF_TUNNEL_UUID__#${CF_TUNNEL_UUID}#g" \
  -e "s#__CF_HOSTNAME__#${CF_HOSTNAME}#g" \
  -e "s#__CF_LOCAL_PORT__#${CF_LOCAL_PORT}#g" \
  -e "s#__CF_CREDENTIAL_FILE__#${CF_CREDENTIAL_FILE}#g" \
  "$CF_TEMPLATE_FILE" > "$CF_CONFIG_FILE"

if grep -q '__CF_' "$CF_CONFIG_FILE"; then
  core_die "Tunnel config still contains unresolved placeholders: $CF_CONFIG_FILE"
fi

core_ok "Tunnel config rendered: $CF_CONFIG_FILE"
