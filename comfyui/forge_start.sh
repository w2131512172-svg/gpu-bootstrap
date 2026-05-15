#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
FORGE_LOG="${FORGE_LOG:-${LOG_DIR}/forge_start.log}"

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

log "============================================================"
log "AI Forge full recovery started"
log "SCRIPT_DIR=$SCRIPT_DIR"
log "LOG_DIR=$LOG_DIR"
log "FORGE_LOG=$FORGE_LOG"
log "============================================================"

# ============================================================
# 1. Environment Layer
# ============================================================
run_step \
  "environment bootstrap" \
  bash "$SCRIPT_DIR/bootstrap.sh"

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
