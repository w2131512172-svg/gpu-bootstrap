#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/config/load_config.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/storage/rclone.sh"

CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/config.env}"
RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"
RCLONE_LOG="${RCLONE_LOG:-/root/rclone_restore.log}"
OLLAMA_HOME="${OLLAMA_HOME:-/root/.ollama}"

core_load_config "$CONFIG_FILE"
core_config_require RCLONE_REMOTE

REMOTE_SOURCE="${RCLONE_REMOTE%/}/.ollama"

core_info "[Ollama Forge] Restoring Ollama data from: $REMOTE_SOURCE"
core_ensure_dir "$OLLAMA_HOME"
core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
core_rclone_check_remote "$REMOTE_SOURCE"

# Transfer policy remains owned by Ollama Forge.
core_rclone_copy "$REMOTE_SOURCE" "$OLLAMA_HOME" \
  --progress \
  --transfers=8 \
  --checkers=8 \
  --fast-list \
  --log-file="$RCLONE_LOG"

core_ok "[Ollama Forge] Restore completed."
core_info "[Ollama Forge] Verifying Ollama state."
ollama list
