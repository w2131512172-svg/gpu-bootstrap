#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# AI Forge - Restore ComfyUI Core
# Responsibility:
#   Restore rebuildable ComfyUI core source only.
#
# Does NOT:
#   - pull R2 assets
#   - install custom node deps
#   - start ComfyUI
#   - start Cloudflare Tunnel
# ============================================================

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
COMFYUI_REPO="${COMFYUI_REPO:-https://github.com/Comfy-Org/ComfyUI.git}"
COMFYUI_VERSION="${COMFYUI_VERSION:-v0.20.1}"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
LOG_FILE="${COMFYUI_CORE_LOG:-$LOG_DIR/comfyui_core_restore.log}"
CORE_INFO_FILE="${COMFYUI_CORE_INFO_FILE:-/root/comfyui_core_info.txt}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "[ERROR] $*"
  exit 1
}

section() {
  log "============================================================"
  log "$*"
  log "============================================================"
}

section "AI Forge ComfyUI core restore started"
log "COMFYUI_ROOT=$COMFYUI_ROOT"
log "COMFYUI_REPO=$COMFYUI_REPO"
log "COMFYUI_VERSION=$COMFYUI_VERSION"
log "LOG_FILE=$LOG_FILE"

command -v git >/dev/null 2>&1 || die "git command not found"

if [ -d "$COMFYUI_ROOT/.git" ]; then
  log "[OK] existing ComfyUI git repo found: $COMFYUI_ROOT"
elif [ -e "$COMFYUI_ROOT" ]; then
  die "COMFYUI_ROOT exists but is not a git repo: $COMFYUI_ROOT"
else
  log "[INFO] cloning ComfyUI core..."
  git clone "$COMFYUI_REPO" "$COMFYUI_ROOT" 2>&1 | tee -a "$LOG_FILE"
fi

cd "$COMFYUI_ROOT"

log "[INFO] fetching tags..."
git fetch --tags 2>&1 | tee -a "$LOG_FILE"

log "[INFO] checking out ComfyUI version: $COMFYUI_VERSION"
git checkout "$COMFYUI_VERSION" 2>&1 | tee -a "$LOG_FILE"

[ -f "$COMFYUI_ROOT/main.py" ] || die "ComfyUI main.py missing after checkout: $COMFYUI_ROOT/main.py"

CURRENT_COMMIT="$(git rev-parse HEAD)"
CURRENT_REF="$(git describe --tags --always 2>/dev/null || git rev-parse --short HEAD)"

cat > "$CORE_INFO_FILE" <<EOF
AI_FORGE_COMFYUI_CORE_INFO
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

COMFYUI_ROOT=$COMFYUI_ROOT
COMFYUI_REPO=$COMFYUI_REPO
COMFYUI_VERSION=$COMFYUI_VERSION
CURRENT_REF=$CURRENT_REF
CURRENT_COMMIT=$CURRENT_COMMIT
EOF

log "[OK] ComfyUI core ready"
log "[INFO] current ref: $CURRENT_REF"
log "[INFO] current commit: $CURRENT_COMMIT"
log "[OK] core info written: $CORE_INFO_FILE"
section "AI Forge ComfyUI core restore completed"
