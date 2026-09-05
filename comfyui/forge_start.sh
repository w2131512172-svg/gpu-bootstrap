#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
FORGE_LOG="${FORGE_LOG:-${LOG_DIR}/forge_start.log}"

TORCH_PROFILE="${TORCH_PROFILE:-auto}"
USER_ENV_NAME="${ENV_NAME:-}"
ENV_NAME="${ENV_NAME:-}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$FORGE_LOG"
}

die() {
  log "[ERROR] $*"
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

    set -a
    # shellcheck disable=SC1091
    source /root/.env
    set +a

    TORCH_PROFILE="${TORCH_PROFILE:-auto}"
    USER_ENV_NAME="${ENV_NAME:-}"
    ENV_NAME="${ENV_NAME:-}"
    MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"
    log "[OK] loaded /root/.env"
  fi

  local rclone_src="${RCLONE_CONF_SRC:-/root/rclone.conf}"
  local rclone_dst="${RCLONE_CONF_DST:-/root/.config/rclone/rclone.conf}"

  mkdir -p "$(dirname "$rclone_dst")"

  if [ -d "$rclone_dst" ]; then
    die "rclone config runtime path is a directory: $rclone_dst"
  fi

  if [ -f "$rclone_src" ]; then
    cp "$rclone_src" "$rclone_dst"
    chmod 600 "$rclone_src" "$rclone_dst"
    log "[OK] rclone config staged: $rclone_src -> $rclone_dst"
  elif [ -f "$rclone_dst" ]; then
    chmod 600 "$rclone_dst"
    log "[OK] rclone runtime config exists: $rclone_dst"
  else
    log "[WARN] rclone config not found yet: $rclone_src or $rclone_dst"
  fi

  mkdir -p /root/.cloudflared

  shopt -s nullglob
  local json_files=(/root/*.json)
  shopt -u nullglob

  if [ "${#json_files[@]}" -gt 0 ]; then
    local json_file
    for json_file in "${json_files[@]}"; do
      cp "$json_file" "/root/.cloudflared/$(basename "$json_file")"
      chmod 600 "$json_file" "/root/.cloudflared/$(basename "$json_file")"
      log "[OK] tunnel credential staged: $json_file -> /root/.cloudflared/$(basename "$json_file")"
    done
  else
    log "[WARN] no /root/*.json tunnel credential found yet"
  fi

  log "[OK] private config preparation completed"
}

install_r2sync_cli() {
  log "============================================================"
  log "[STEP] install r2sync CLI"
  log "============================================================"

  local r2sync_src="$SCRIPT_DIR/r2-sync/r2sync"
  local r2sync_dst="/usr/local/bin/r2sync"

  if [ ! -f "$r2sync_src" ]; then
    die "r2sync source not found: $r2sync_src"
  fi

  chmod +x "$r2sync_src"
  ln -sf "$r2sync_src" "$r2sync_dst"

  log "[OK] r2sync executable prepared: $r2sync_src"
  log "[OK] r2sync symlink installed: $r2sync_dst -> $r2sync_src"
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

install_r2sync_cli

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
  "dependency self-check" \
  bash "$SCRIPT_DIR/deps/check_deps.sh"

run_step \
  "dependency install" \
  python "$SCRIPT_DIR/deps/auto_deps.py"

run_step \
  "comfyui-sam3 isolation env repair" \
  bash "$SCRIPT_DIR/deps/fix_sam3_env.sh"

run_step \
  "service startup" \
  bash "$SCRIPT_DIR/start_all.sh" start

log "============================================================"
log "[SUCCESS] AI Forge full recovery completed 🚀"
log "[INFO] r2sync CLI available: r2sync help"
log "============================================================"
