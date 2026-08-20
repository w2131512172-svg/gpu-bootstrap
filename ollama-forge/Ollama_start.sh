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

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
OLLAMA_LIFECYCLE_LOG="${OLLAMA_LIFECYCLE_LOG:-${LOG_DIR}/ollama.log}"
core_log_init ollama.lifecycle "$OLLAMA_LIFECYCLE_LOG"

if [ -f "$CONFIG_FILE" ]; then
  core_load_config "$CONFIG_FILE"
else
  core_warn config.missing "Ollama Forge config was not found; using defaults" \
    "path=$CONFIG_FILE"
fi

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_SERVICE_LOG="${OLLAMA_SERVICE_LOG:-${OLLAMA_LOG:-${LOG_DIR}/ollama-service.log}}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:${OLLAMA_PORT}}"
export OLLAMA_HOST

core_info service.start.requested "Starting Ollama" \
  "host=$OLLAMA_HOST" "service_log=$OLLAMA_SERVICE_LOG"
core_gpu_assign_forge ollama

if ! pgrep -x ollama >/dev/null 2>&1; then
  mkdir -p "$(dirname "$OLLAMA_SERVICE_LOG")"
  nohup ollama serve > "$OLLAMA_SERVICE_LOG" 2>&1 &
  ollama_pid=$!
  core_info service.process.started "Ollama process launched" \
    "pid=$ollama_pid" "service_log=$OLLAMA_SERVICE_LOG"
  sleep 5
else
  core_info service.already_running "Ollama is already running"
fi

if ! ollama list >/dev/null; then
  core_error service.health.failed "Ollama health check failed" \
    "host=$OLLAMA_HOST" "service_log=$OLLAMA_SERVICE_LOG"
  tail -n 80 "$OLLAMA_SERVICE_LOG" >&2 || true
  exit 1
fi

core_ok service.ready "Ollama is ready" "host=$OLLAMA_HOST"
core_info service.endpoint "Ollama endpoint is available" \
  "url=http://${OLLAMA_HOST}" "lifecycle_log=$OLLAMA_LIFECYCLE_LOG" \
  "service_log=$OLLAMA_SERVICE_LOG"
