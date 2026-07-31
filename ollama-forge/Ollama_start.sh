#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/config/load_config.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/hardware/gpu_assignment.sh"

CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/config.env}"
if [ -f "$CONFIG_FILE" ]; then
  core_load_config "$CONFIG_FILE"
fi

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_LOG="${OLLAMA_LOG:-/root/ollama.log}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:${OLLAMA_PORT}}"
export OLLAMA_HOST

core_info "[Ollama Forge] Starting Ollama."
core_gpu_assign_forge ollama

if ! pgrep -x ollama >/dev/null 2>&1; then
  nohup ollama serve > "$OLLAMA_LOG" 2>&1 &
  sleep 5
else
  core_info "[Ollama Forge] Ollama is already running."
fi

if ! ollama list >/dev/null; then
  core_error "[Ollama Forge] Ollama health check failed."
  tail -n 80 "$OLLAMA_LOG" || true
  exit 1
fi

core_ok "[Ollama Forge] Ollama is ready."
core_info "[Ollama Forge] API: http://${OLLAMA_HOST}"
core_info "[Ollama Forge] Log: $OLLAMA_LOG"
