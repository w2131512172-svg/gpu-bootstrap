#!/usr/bin/env bash
set -euo pipefail

# Ollama Forge one-click restore orchestration.
# Open WebUI is intentionally not part of Ollama Forge.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/config/load_config.sh"

FORGE_ROOT="${FORGE_ROOT:-${SCRIPT_DIR}}"
CONFIG_FILE="${CONFIG_FILE:-${FORGE_ROOT}/config.env}"
CONFIG_TEMPLATE="${CONFIG_TEMPLATE:-${FORGE_ROOT}/config.env.example}"
CHECK_COMMON_TOOLS="${FORGE_ROOT}/check_common_tools.sh"
RESTORE_SCRIPT="${FORGE_ROOT}/restore_from_r2.sh"
START_ALL_SCRIPT="${FORGE_ROOT}/Ollama_start.sh"
CLI_INSTALLER="${REPO_ROOT}/core/cli/install.sh"
LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
RECOVERY_LOG="${RECOVERY_LOG:-${LOG_DIR}/recovery.log}"
OLLAMA_LIFECYCLE_LOG="${OLLAMA_LIFECYCLE_LOG:-${LOG_DIR}/ollama.log}"
OLLAMA_SERVICE_LOG="${OLLAMA_SERVICE_LOG:-${OLLAMA_LOG:-${LOG_DIR}/ollama-service.log}}"
RCLONE_LOG="${RCLONE_LOG:-${LOG_DIR}/rclone.log}"

core_log_init ollama.recovery "$RECOVERY_LOG"

prepare_config() {
  if [ -f "$CONFIG_FILE" ]; then
    chmod 600 "$CONFIG_FILE"
    core_ok config.ready "Ollama Forge config is ready" "path=$CONFIG_FILE"
    return 0
  fi

  core_require_file "$CONFIG_TEMPLATE"
  cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  core_ok config.created "Ollama Forge config was created from the template" \
    "template=$CONFIG_TEMPLATE" "path=$CONFIG_FILE"
}

run_script() {
  local script="$1"
  shift || true

  core_require_file "$script"
  core_run_step "$(basename "$script")" bash "$script" "$@"
}

main() {
  core_require_root
  core_info recovery.start "Ollama Forge recovery started"

  run_script "$CLI_INSTALLER"
  prepare_config
  core_load_config "$CONFIG_FILE"
  run_script "$CHECK_COMMON_TOOLS"
  run_script "$RESTORE_SCRIPT"

  run_script "$START_ALL_SCRIPT"

  core_ok recovery.complete "Ollama Forge recovery completed" \
    "port=${OLLAMA_PORT:-11434}" \
    "lifecycle_log=$OLLAMA_LIFECYCLE_LOG" \
    "service_log=$OLLAMA_SERVICE_LOG" \
    "rclone_log=$RCLONE_LOG"
}

main "$@"
