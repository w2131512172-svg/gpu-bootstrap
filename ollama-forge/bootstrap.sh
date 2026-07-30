#!/usr/bin/env bash
set -euo pipefail

# Ollama Forge runtime bootstrap.
# Shared system prerequisites are delegated to Core through
# check_common_tools.sh. Python venv, Ollama, and Open WebUI stay in Forge.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"

FORGE_ROOT="${FORGE_ROOT:-${SCRIPT_DIR}}"
DATA_ROOT="${DATA_ROOT:-/root/ollama-forge-data}"
VENV_DIR="${VENV_DIR:-${FORGE_ROOT}/venv}"

ollama_log() {
  core_info "[Ollama Forge][bootstrap] $*"
}

main() {
  core_require_root

  ollama_log "Bootstrap started."
  bash "${SCRIPT_DIR}/check_common_tools.sh"

  ollama_log "Creating Forge data directories."
  core_ensure_dir "${DATA_ROOT}/open-webui"
  core_ensure_dir /root/.ollama

  if [ ! -x "${VENV_DIR}/bin/python" ]; then
    ollama_log "Creating Python venv: $VENV_DIR"
    python3.11 -m venv "$VENV_DIR"
  else
    ollama_log "Python venv already exists: $VENV_DIR"
  fi

  # shellcheck disable=SC1090
  source "${VENV_DIR}/bin/activate"

  ollama_log "Installing or updating Open WebUI."
  python -m pip install --upgrade pip
  python -m pip install --upgrade open-webui

  ollama_log "Bootstrap completed."
  echo "ollama:      $(ollama --version 2>/dev/null || true)"
  echo "rclone:      $(rclone version 2>/dev/null | head -n 1 || true)"
  echo "cloudflared: $(cloudflared --version 2>/dev/null || true)"
  echo "python:      $(python --version 2>/dev/null || true)"
  echo "ffmpeg:      $(ffmpeg -version 2>/dev/null | head -n 1 || true)"
}

main "$@"
