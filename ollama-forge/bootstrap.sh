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

ollama_log() {
  core_info "[Ollama Forge][bootstrap] $*"
}

main() {
  core_require_root

  ollama_log "Bootstrap started."
  bash "${SCRIPT_DIR}/check_common_tools.sh"

  ollama_log "Preparing Ollama data directory."
  core_ensure_dir "$OLLAMA_HOME"

  ollama_log "Bootstrap completed."
  echo "ollama:      $(ollama --version 2>/dev/null || true)"
  echo "rclone:      $(rclone version 2>/dev/null | head -n 1 || true)"
  echo "ffmpeg:      $(ffmpeg -version 2>/dev/null | head -n 1 || true)"
}

main "$@"
