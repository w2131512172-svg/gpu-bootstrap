#!/usr/bin/env bash
set -euo pipefail

# EverForge / Ollama Forge one-click restore orchestration entry.
#
# This script does not replace bootstrap.sh.
# It only coordinates existing scripts in a safe order:
#   1. Check/install common system tools.
#   2. Check required config.env.
#   3. Ensure Open WebUI venv exists, using bootstrap.sh only when needed.
#   4. Restore Ollama data from R2.
#   5. Pull missing models from models.txt.
#   6. Start Ollama + Open WebUI.

FORGE_ROOT="/root/ollama-forge"
CONFIG_FILE="$FORGE_ROOT/config.env"
CHECK_COMMON_TOOLS="$FORGE_ROOT/check_common_tools.sh"
BOOTSTRAP_SCRIPT="$FORGE_ROOT/bootstrap.sh"
RESTORE_SCRIPT="$FORGE_ROOT/restore_from_r2.sh"
PULL_MODELS_SCRIPT="$FORGE_ROOT/pull_models.sh"
START_ALL_SCRIPT="$FORGE_ROOT/start_all.sh"
VENV_DIR="$FORGE_ROOT/venv"

log() {
  echo "[Ollama Forge][restore] $*"
}

fail() {
  echo "[Ollama Forge][restore][ERROR] $*" >&2
  exit 1
}

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "Please run as root."
  fi
}

require_file() {
  local file="$1"
  local hint="${2:-}"

  if [ ! -f "$file" ]; then
    if [ -n "$hint" ]; then
      fail "Missing file: $file. $hint"
    else
      fail "Missing file: $file"
    fi
  fi
}

run_script() {
  local script="$1"
  shift || true

  require_file "$script"
  log "Running: $script $*"
  bash "$script" "$@"
}

load_config() {
  require_file "$CONFIG_FILE" "Copy config.env.example to config.env and fill required values first."
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  : "${OPEN_WEBUI_PORT:=3000}"
  : "${OPEN_WEBUI_DATA:=/root/ollama-forge-data/open-webui}"
}

ensure_common_tools() {
  run_script "$CHECK_COMMON_TOOLS"
}

ensure_open_webui_env() {
  if [ -x "$VENV_DIR/bin/python" ]; then
    log "Open WebUI venv exists: $VENV_DIR"
    return 0
  fi

  log "Open WebUI venv missing. Running bootstrap.sh to initialize Ollama Forge runtime..."
  run_script "$BOOTSTRAP_SCRIPT"

  if [ ! -x "$VENV_DIR/bin/python" ]; then
    fail "Open WebUI venv still missing after bootstrap: $VENV_DIR"
  fi
}

restore_from_r2() {
  run_script "$RESTORE_SCRIPT"
}

pull_models() {
  if [ -f "$FORGE_ROOT/models.txt" ]; then
    run_script "$PULL_MODELS_SCRIPT"
  else
    log "models.txt not found, skipping model pull."
  fi
}

start_services() {
  run_script "$START_ALL_SCRIPT"
}

print_summary() {
  echo
  log "Restore orchestration completed."
  echo "Ollama API:   http://127.0.0.1:11434"
  echo "Open WebUI:   http://127.0.0.1:${OPEN_WEBUI_PORT}"
  echo "Ollama log:   /root/ollama.log"
  echo "WebUI log:    /root/open-webui.log"
  echo "Rclone log:   /root/rclone_restore.log"
}

main() {
  need_root

  log "Starting Ollama Forge restore orchestration..."

  ensure_common_tools
  load_config
  ensure_open_webui_env
  restore_from_r2
  pull_models
  start_services
  print_summary
}

main "$@"
