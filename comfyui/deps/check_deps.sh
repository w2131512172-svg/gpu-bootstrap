#!/usr/bin/env bash
set -u

LOG_DIR="/root/everspark_logs"
LOG_FILE="$LOG_DIR/deps_check.log"
AUTO_DEPS_LOG="$LOG_DIR/auto_deps.log"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMFYUI_ROOT="${EVERSPARK_COMFYUI_ROOT:-/root/ComfyUI}"
CUSTOM_NODES_DIR="$COMFYUI_ROOT/custom_nodes"

AUTO_DEPS_PY="$SCRIPT_DIR/auto_deps.py"
CLEAN_FILE="$SCRIPT_DIR/custom_nodes.clean.txt"
SKIPPED_FILE="$SCRIPT_DIR/custom_nodes.skipped.txt"
MANUAL_FILE="$SCRIPT_DIR/manual_requirements.txt"
COMPAT_FILE="$SCRIPT_DIR/compat_requirements.txt"

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

check_file_exists() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    ok "$label exists: $path"
  else
    fail "$label missing: $path"
  fi
}

check_file_readable() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ] && [ -r "$path" ]; then
    ok "$label readable: $path"
  elif [ -f "$path" ]; then
    fail "$label exists but is not readable: $path"
  else
    fail "$label missing: $path"
  fi
}

check_optional_file_readable() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ] && [ -r "$path" ]; then
    ok "$label readable: $path"
  elif [ -f "$path" ]; then
    fail "$label exists but is not readable: $path"
  else
    warn "$label not found, allowed if not needed yet: $path"
  fi
}

CHECK_FAILED=0

log "EverSpark Forge dependency layer self-check started"
log "script dir: $SCRIPT_DIR"
log "ComfyUI root: $COMFYUI_ROOT"
log "log file: $LOG_FILE"

# ===== structure checks =====
check_file_exists "$AUTO_DEPS_PY" "auto_deps.py"
check_file_readable "$CLEAN_FILE" "custom_nodes.clean.txt"
check_file_readable "$SKIPPED_FILE" "custom_nodes.skipped.txt"
check_optional_file_readable "$MANUAL_FILE" "manual_requirements.txt"
check_optional_file_readable "$COMPAT_FILE" "compat_requirements.txt"

if [ -d "$COMFYUI_ROOT" ]; then
  ok "ComfyUI root exists: $COMFYUI_ROOT"
else
  fail "ComfyUI root missing: $COMFYUI_ROOT"
fi

if [ -d "$CUSTOM_NODES_DIR" ]; then
  ok "custom_nodes exists: $CUSTOM_NODES_DIR"
else
  warn "custom_nodes not found yet, allowed before data restore: $CUSTOM_NODES_DIR"
fi

# ===== python environment checks =====
if command -v python >/dev/null 2>&1; then
  PY_BIN="$(command -v python)"
  ok "python found: $PY_BIN"
  python --version 2>&1 | tee -a "$LOG_FILE"
else
  fail "python command not found"
fi

if python -m pip --version >> "$LOG_FILE" 2>&1; then
  ok "pip available"
else
  fail "pip unavailable via python -m pip"
fi

if python - <<'PY' >> "$LOG_FILE" 2>&1
try:
    import tomli
    print(f"tomli available: {tomli.__version__}")
except Exception as exc:
    raise SystemExit(f"tomli unavailable: {exc}")
PY
then
  ok "tomli available"
else
  fail "tomli unavailable"
fi

# ===== dependency artifact checks =====
if [ -f "$CLEAN_FILE" ]; then
  CLEAN_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$CLEAN_FILE" | wc -l | tr -d ' ')"
  log "custom_nodes.clean.txt active lines: $CLEAN_LINES"
  if [ "$CLEAN_LINES" -gt 0 ]; then
    ok "clean dependency list is not empty"
  else
    warn "clean dependency list is empty; run: python auto_deps.py --rescan --scan-only"
  fi
fi

if [ -f "$SKIPPED_FILE" ]; then
  SKIPPED_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$SKIPPED_FILE" | wc -l | tr -d ' ')"
  log "custom_nodes.skipped.txt active lines: $SKIPPED_LINES"
fi

if [ -f "$MANUAL_FILE" ]; then
  MANUAL_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$MANUAL_FILE" | wc -l | tr -d ' ')"
  log "manual_requirements.txt active lines: $MANUAL_LINES"
fi

if [ -f "$COMPAT_FILE" ]; then
  COMPAT_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$COMPAT_FILE" | wc -l | tr -d ' ')"
  log "compat_requirements.txt active lines: $COMPAT_LINES"
fi

# ===== auto_deps log checks =====
if [ -f "$AUTO_DEPS_LOG" ]; then
  ok "auto_deps log exists: $AUTO_DEPS_LOG"

  if grep -qE '\[auto_deps\] DONE( |$)|\[auto_deps\] DONE scan-only|\[auto_deps\] DONE repair-log' "$AUTO_DEPS_LOG"; then
    ok "auto_deps log contains DONE marker"
  else
    warn "auto_deps log exists but no DONE marker found"
  fi
else
  warn "auto_deps log not found yet; run auto_deps.py once to generate it: $AUTO_DEPS_LOG"
fi

if [ "$CHECK_FAILED" -eq 0 ]; then
  ok "dependency layer self-check PASSED"
  exit 0
else
  fail "dependency layer self-check FAILED"
  exit 1
fi
