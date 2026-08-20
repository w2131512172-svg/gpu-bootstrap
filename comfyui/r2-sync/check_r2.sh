#!/usr/bin/env bash
set -u

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="$LOG_DIR/r2_check.log"

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_REMOTE="${R2_REMOTE:-r2-assets:comfyui-assets/ComfyUI}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

R2_PULL_LOG="$LOG_DIR/r2_pull.log"
R2_PUSH_LOG="$LOG_DIR/r2_push.log"

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

ok() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $*" | tee -a "$LOG_FILE"
}

warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE"
}

fail() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE"
  CHECK_FAILED=1
}

CHECK_FAILED=0

log "EverSpark Forge R2 data layer self-check started"
log "COMFYUI_ROOT=$COMFYUI_ROOT"
log "R2_REMOTE=$R2_REMOTE"
log "LOG_FILE=$LOG_FILE"

# ===== rclone binary =====
if core_rclone_require; then
  ok "rclone found: $(command -v rclone)"
  rclone version | head -n 1 | tee -a "$LOG_FILE"
else
  fail "rclone command not found"
fi

# ===== rclone config =====
# Self-heal the runtime config so this check is safe to run independently.
if ! core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"; then
  fail "unable to install rclone runtime config"
fi

if [ -d "$RCLONE_CONF_SRC" ]; then
  fail "RCLONE_CONF_SRC is a directory: $RCLONE_CONF_SRC"
elif [ -f "$RCLONE_CONF_SRC" ]; then
  ok "rclone source config exists: $RCLONE_CONF_SRC"
else
  warn "rclone source config not found: $RCLONE_CONF_SRC"
fi

if [ -d "$RCLONE_CONF_DST" ]; then
  fail "RCLONE_CONF_DST is a directory: $RCLONE_CONF_DST"
elif [ -f "$RCLONE_CONF_DST" ]; then
  ok "rclone runtime config exists: $RCLONE_CONF_DST"
else
  fail "rclone runtime config missing: $RCLONE_CONF_DST"
fi

# ===== remote availability =====
if core_rclone_lsd "$R2_REMOTE" >> "$LOG_FILE" 2>&1; then
  ok "R2 remote accessible: $R2_REMOTE"
else
  fail "unable to access R2 remote: $R2_REMOTE"
fi

# ===== local comfyui =====
if [ -d "$COMFYUI_ROOT" ]; then
  ok "ComfyUI root exists: $COMFYUI_ROOT"
else
  fail "ComfyUI root missing: $COMFYUI_ROOT"
fi

if [ -f "$COMFYUI_ROOT/main.py" ]; then
  ok "ComfyUI core detected"
else
  warn "ComfyUI core missing: $COMFYUI_ROOT/main.py"
fi

# ===== logs =====
if [ -f "$R2_PULL_LOG" ]; then
  ok "R2 pull log exists: $R2_PULL_LOG"
else
  warn "R2 pull log not found yet: $R2_PULL_LOG"
fi

if [ -f "$R2_PUSH_LOG" ]; then
  ok "R2 push log exists: $R2_PUSH_LOG"
else
  warn "R2 push log not found yet: $R2_PUSH_LOG"
fi

# ===== final =====
if [ "$CHECK_FAILED" -eq 0 ]; then
  ok "R2 data layer self-check PASSED"
  exit 0
else
  fail "R2 data layer self-check FAILED"
  exit 1
fi
