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
CHECK_COMMON_TOOLS="${FORGE_ROOT}/check_common_tools.sh"
RESTORE_SCRIPT="${FORGE_ROOT}/restore_from_r2.sh"
START_ALL_SCRIPT="${FORGE_ROOT}/start_all.sh"

run_script() {
  local script="$1"
  shift || true

  core_require_file "$script"
  core_info "[Ollama Forge][restore] Running: $script $*"
  bash "$script" "$@"
}

main() {
  core_require_root
  core_info "[Ollama Forge][restore] Restore started."

  run_script "$CHECK_COMMON_TOOLS"
  core_load_config "$CONFIG_FILE"
  run_script "$RESTORE_SCRIPT"

  run_script "$START_ALL_SCRIPT"

  core_ok "[Ollama Forge][restore] Restore completed."
  core_info "Ollama API: http://127.0.0.1:${OLLAMA_PORT:-11434}"
  core_info "Ollama log: ${OLLAMA_LOG:-/root/ollama.log}"
  core_info "Rclone log: ${RCLONE_LOG:-/root/rclone_restore.log}"
}

main "$@"
