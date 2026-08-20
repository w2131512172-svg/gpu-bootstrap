#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/config/load_config.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/storage/rclone.sh"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
FORGE_LOG="${FORGE_LOG:-${LOG_DIR}/forge_start.log}"

TORCH_PROFILE="${TORCH_PROFILE:-auto}"
USER_ENV_NAME="${ENV_NAME:-}"
ENV_NAME="${ENV_NAME:-}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

mkdir -p "$LOG_DIR"
CORE_LOG_FILE="$FORGE_LOG"
export CORE_LOG_FILE

log() {
  core_info "$@"
}

die() {
  core_error "$@"
  exit 1
}

run_step() {
  local name="$1"
  shift

  log "============================================================"
  log "[STEP] $name"
  log "[RUN ] $*"
  log "============================================================"

  if "$@"; then
    log "[OK] $name completed"
  else
    die "$name failed"
  fi
}

run_optional_step() {
  local name="$1"
  shift

  log "============================================================"
  log "[OPTIONAL] $name"
  log "[RUN     ] $*"
  log "============================================================"

  if "$@"; then
    log "[OK] optional step completed: $name"
  else
    local exit_code=$?
    core_warn "optional step failed (exit=$exit_code): $name"
    core_warn "continuing recovery because this component is not required for the ComfyUI Forge core"
  fi
}

prepare_private_configs() {
  log "============================================================"
  log "[STEP] prepare private config files"
  log "============================================================"

  if [ ! -f /root/.env ] && [ -f /root/env.txt ]; then
    mv /root/env.txt /root/.env
    log "[OK] normalized /root/env.txt -> /root/.env"
  elif [ -f /root/.env ]; then
    log "[OK] /root/.env exists"
  else
    log "[WARN] /root/.env not found; allowed if defaults are enough"
  fi

  if [ -f /root/.env ]; then
    chmod 600 /root/.env
    log "[OK] chmod 600 /root/.env"

    core_load_config /root/.env

    TORCH_PROFILE="${TORCH_PROFILE:-auto}"
    USER_ENV_NAME="${ENV_NAME:-}"
    ENV_NAME="${ENV_NAME:-}"
    MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"
    log "[OK] loaded /root/.env"
  fi

  local rclone_src="${RCLONE_CONF_SRC:-/root/rclone.conf}"
  local rclone_dst="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

  if [ -f "$rclone_src" ] || [ -f "$rclone_dst" ]; then
    core_rclone_ensure_config "$rclone_src" "$rclone_dst"
    [ ! -f "$rclone_src" ] || chmod 600 "$rclone_src"
  else
    log "[WARN] rclone config not found yet: $rclone_src or $rclone_dst"
  fi

  log "[OK] private config preparation completed"
}

install_everspark_cli() {
  log "============================================================"
  log "[STEP] install EverSpark Forge CLI"
  log "============================================================"

  local installer="${REPO_ROOT}/core/cli/install.sh"
  if [ ! -f "$installer" ]; then
    die "EverSpark CLI installer not found: $installer"
  fi

  bash "$installer"
  log "[OK] EverSpark Forge CLI is available: everspark help"
}

detect_torch_profile() {
  if [ "$TORCH_PROFILE" != "auto" ]; then
    log "[INFO] TORCH_PROFILE forced by env: $TORCH_PROFILE"
  else
    local detector="$SCRIPT_DIR/detect_torch_profile.sh"

    [ -f "$detector" ] || die "detect_torch_profile.sh not found: $detector"

    TORCH_PROFILE="$(bash "$detector")"

    log "[INFO] detected TORCH_PROFILE=$TORCH_PROFILE"
  fi

  case "$TORCH_PROFILE" in
    cu128)
      if [ -n "$USER_ENV_NAME" ]; then
        ENV_NAME="$USER_ENV_NAME"
        log "[INFO] ENV_NAME forced by env: $ENV_NAME"
      else
        ENV_NAME="torch-cu128"
      fi
      ;;
    cu121)
      if [ -n "$USER_ENV_NAME" ]; then
        ENV_NAME="$USER_ENV_NAME"
        log "[INFO] ENV_NAME forced by env: $ENV_NAME"
      else
        ENV_NAME="torch251-cu121"
      fi
      ;;
    *)
      die "unsupported TORCH_PROFILE: $TORCH_PROFILE"
      ;;
  esac

  export TORCH_PROFILE
  export ENV_NAME
}

activate_project_env() {
  log "============================================================"
  log "[STEP] activate project conda env"
  log "[INFO] TORCH_PROFILE=$TORCH_PROFILE"
  log "[INFO] ENV_NAME=$ENV_NAME"
  log "[INFO] MINICONDA_DIR=$MINICONDA_DIR"
  log "============================================================"

  local conda_sh="${MINICONDA_DIR}/etc/profile.d/conda.sh"

  if [ ! -f "$conda_sh" ]; then
    die "conda.sh not found: $conda_sh"
  fi

  # shellcheck disable=SC1090
  source "$conda_sh"
  conda activate "$ENV_NAME"

  command -v python >/dev/null 2>&1 || die "python not found after conda activate"

  log "[OK] conda env activated: $ENV_NAME"
  log "[INFO] python: $(command -v python)"
  log "[INFO] python version: $(python --version 2>&1)"
}

log "============================================================"
log "AI Forge full recovery started"
log "SCRIPT_DIR=$SCRIPT_DIR"
log "LOG_DIR=$LOG_DIR"
log "FORGE_LOG=$FORGE_LOG"
log "============================================================"

prepare_private_configs

install_everspark_cli

detect_torch_profile

case "$TORCH_PROFILE" in
  cu128)
    BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-cu128.sh"
    ;;
  cu121)
    BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-cu121.sh"
    ;;
  *)
    die "unsupported TORCH_PROFILE: $TORCH_PROFILE"
    ;;
esac

log "[INFO] selected bootstrap: $BOOTSTRAP_SCRIPT"
log "[INFO] selected conda env: $ENV_NAME"

run_step \
  "environment bootstrap" \
  bash "$BOOTSTRAP_SCRIPT"

activate_project_env

run_step \
  "restore ComfyUI core" \
  bash "$SCRIPT_DIR/restore_comfyui_core.sh"

run_step \
  "R2 self-check" \
  bash "$SCRIPT_DIR/r2-sync/check_r2.sh"

run_step \
  "R2 asset pull" \
  bash "$SCRIPT_DIR/r2-sync/pull_from_r2.sh"

run_step \
  "dependency self-check" \
  bash "$SCRIPT_DIR/deps/check_deps.sh"

run_step \
  "dependency install" \
  python "$SCRIPT_DIR/deps/auto_deps.py"

run_optional_step \
  "comfyui-sam3 isolation env repair" \
  bash "$SCRIPT_DIR/deps/fix_sam3_env.sh"

run_step \
  "service startup" \
  bash "$SCRIPT_DIR/start_all.sh" start

log "============================================================"
log "[SUCCESS] AI Forge full recovery completed 🚀"
log "[INFO] EverSpark Forge CLI available: everspark help"
log "============================================================"
