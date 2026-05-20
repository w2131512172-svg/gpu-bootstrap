#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
FORGE_LOG="${FORGE_LOG:-${LOG_DIR}/forge_start.log}"

ENV_NAME="${ENV_NAME:-torch251-cu121}"
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

  # Some upload panels cannot easily upload a dotfile named .env.
  # Allow uploading /root/env.txt and normalize it to /root/.env.
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

    # Load env early so the rest of forge_start can use user overrides.
    set -a
    # shellcheck disable=SC1091
    source /root/.env
    set +a

    ENV_NAME="${ENV_NAME:-torch251-cu121}"
    MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"
    log "[OK] loaded /root/.env"
  fi

  # Stage rclone config from the common upload location to rclone's runtime path.
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

  # Stage Cloudflare Tunnel credentials uploaded as /root/*.json.
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

activate_project_env() {
  log "============================================================"
  log "[STEP] activate project conda env"
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

# ============================================================
# 0. Private Config Preparation
# ============================================================
prepare_private_configs

# ============================================================
# 1. Environment Layer
# ============================================================
run_step \
  "environment bootstrap" \
  bash "$SCRIPT_DIR/bootstrap.sh"

# The bootstrap script runs in a child process. Re-activate the
# project conda env in this parent process so later layers can use python/pip.
activate_project_env

# ============================================================
# 2. Restore ComfyUI Core
# ============================================================
run_step \
  "restore ComfyUI core" \
  bash "$SCRIPT_DIR/restore_comfyui_core.sh"

# ============================================================
# 3. Data Layer Self-check
# ============================================================
run_step \
  "R2 self-check" \
  bash "$SCRIPT_DIR/r2-sync/check_r2.sh"

# ============================================================
# 4. Data Layer Pull
# ============================================================
run_step \
  "R2 asset pull" \
  bash "$SCRIPT_DIR/r2-sync/pull_from_r2.sh"

# ============================================================
# 5. Dependency Layer Self-check
# ============================================================
run_step \
  "dependency self-check" \
  bash "$SCRIPT_DIR/deps/check_deps.sh"

# ============================================================
# 6. Dependency Install
# ============================================================
run_step \
  "dependency install" \
  python "$SCRIPT_DIR/deps/auto_deps.py"

# ============================================================
# 7. First Service Start
# ============================================================
run_step \
  "service startup" \
  bash "$SCRIPT_DIR/start_all.sh" start

log "============================================================"
log "[SUCCESS] AI Forge full recovery completed 🚀"
log "============================================================"
