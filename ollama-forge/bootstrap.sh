#!/usr/bin/env bash
set -euo pipefail

# Ollama Forge runtime bootstrap.
# Shared system prerequisites are delegated to Core through
# check_common_tools.sh. Ollama remains the Forge runtime.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"

OLLAMA_HOME="${OLLAMA_HOME:-/root/.ollama}"
LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-${LOG_DIR}/bootstrap.log}"
core_log_init ollama.bootstrap "$BOOTSTRAP_LOG"

main() {
  core_require_root

  core_info bootstrap.start "Ollama Forge bootstrap started"
  core_run_step prerequisites bash "${SCRIPT_DIR}/check_common_tools.sh"

  core_info data.prepare "Preparing Ollama data directory" "path=$OLLAMA_HOME"
  core_ensure_dir "$OLLAMA_HOME"

  core_ok bootstrap.complete "Ollama Forge bootstrap completed" \
    "ollama_version=$(ollama --version 2>/dev/null || true)" \
    "rclone_version=$(rclone version 2>/dev/null | head -n 1 || true)" \
    "ffmpeg_version=$(ffmpeg -version 2>/dev/null | head -n 1 || true)"
}

main "$@"
