#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="$LOG_DIR/deps_check.log"
AUTO_DEPS_LOG="$LOG_DIR/auto_deps.log"
COMFYUI_ROOT="${EVERSPARK_COMFYUI_ROOT:-/root/ComfyUI}"
CUSTOM_NODES_DIR="$COMFYUI_ROOT/custom_nodes"

AUTO_DEPS_PY="$SCRIPT_DIR/auto_deps.py"
CLEAN_FILE="$SCRIPT_DIR/custom_nodes.clean.txt"
SKIPPED_FILE="$SCRIPT_DIR/custom_nodes.skipped.txt"
MANUAL_FILE="$SCRIPT_DIR/manual_requirements.txt"
COMPAT_FILE="$SCRIPT_DIR/compat_requirements.txt"

core_log_init dependencies.check "$LOG_FILE"
: > "$LOG_FILE"

record_failure() {
  core_error dependency.check "$@"
  CHECK_FAILED=1
}

check_file_exists() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    core_ok dependency.check "$label exists: $path"
  else
    record_failure "$label missing: $path"
  fi
}

check_file_readable() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ] && [ -r "$path" ]; then
    core_ok dependency.check "$label readable: $path"
  elif [ -f "$path" ]; then
    record_failure "$label exists but is not readable: $path"
  else
    record_failure "$label missing: $path"
  fi
}

check_optional_file_readable() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ] && [ -r "$path" ]; then
    core_ok dependency.check "$label readable: $path"
  elif [ -f "$path" ]; then
    record_failure "$label exists but is not readable: $path"
  else
    core_warn dependency.check "$label not found, allowed if not needed yet: $path"
  fi
}

CHECK_FAILED=0

core_info dependency.check "EverSpark Forge dependency layer self-check started"
core_info dependency.check "script dir: $SCRIPT_DIR"
core_info dependency.check "ComfyUI root: $COMFYUI_ROOT"
core_info dependency.check "log file: $LOG_FILE"

# ===== structure checks =====
check_file_exists "$AUTO_DEPS_PY" "auto_deps.py"
check_file_readable "$CLEAN_FILE" "custom_nodes.clean.txt"
check_file_readable "$SKIPPED_FILE" "custom_nodes.skipped.txt"
check_optional_file_readable "$MANUAL_FILE" "manual_requirements.txt"
check_optional_file_readable "$COMPAT_FILE" "compat_requirements.txt"

if [ -d "$COMFYUI_ROOT" ]; then
  core_ok dependency.check "ComfyUI root exists: $COMFYUI_ROOT"
else
  record_failure "ComfyUI root missing: $COMFYUI_ROOT"
fi

if [ -d "$CUSTOM_NODES_DIR" ]; then
  core_ok dependency.check "custom_nodes exists: $CUSTOM_NODES_DIR"
else
  core_warn dependency.check "custom_nodes not found yet, allowed before data restore: $CUSTOM_NODES_DIR"
fi

# ===== python environment checks =====
if command -v python >/dev/null 2>&1; then
  PY_BIN="$(command -v python)"
  PY_VERSION="$(python --version 2>&1)"
  core_ok dependency.check "python found" "path=$PY_BIN" "version=$PY_VERSION"
else
  record_failure "python command not found"
fi

if PIP_VERSION="$(python -m pip --version 2>&1)"; then
  core_ok dependency.check "pip available" "version=$PIP_VERSION"
else
  record_failure "pip unavailable via python -m pip"
fi

if TOMLI_VERSION="$(python - <<'PY'
try:
    import tomli
    print(tomli.__version__)
except Exception as exc:
    raise SystemExit(f"tomli unavailable: {exc}")
PY
)"
then
  core_ok dependency.check "tomli available" "version=$TOMLI_VERSION"
else
  record_failure "tomli unavailable"
fi

# ===== dependency artifact checks =====
if [ -f "$CLEAN_FILE" ]; then
  CLEAN_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$CLEAN_FILE" | wc -l | tr -d ' ')"
  core_info dependency.check "custom_nodes.clean.txt active lines: $CLEAN_LINES"
  if [ "$CLEAN_LINES" -gt 0 ]; then
    core_ok dependency.check "clean dependency list is not empty"
  else
    core_warn dependency.check "clean dependency list is empty; run: python auto_deps.py --rescan --scan-only"
  fi
fi

if [ -f "$SKIPPED_FILE" ]; then
  SKIPPED_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$SKIPPED_FILE" | wc -l | tr -d ' ')"
  core_info dependency.check "custom_nodes.skipped.txt active lines: $SKIPPED_LINES"
fi

if [ -f "$MANUAL_FILE" ]; then
  MANUAL_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$MANUAL_FILE" | wc -l | tr -d ' ')"
  core_info dependency.check "manual_requirements.txt active lines: $MANUAL_LINES"
fi

if [ -f "$COMPAT_FILE" ]; then
  COMPAT_LINES="$(grep -vE '^[[:space:]]*(#|$)' "$COMPAT_FILE" | wc -l | tr -d ' ')"
  core_info dependency.check "compat_requirements.txt active lines: $COMPAT_LINES"
fi

# ===== auto_deps log checks =====
if [ -f "$AUTO_DEPS_LOG" ]; then
  core_ok dependency.check "auto_deps log exists: $AUTO_DEPS_LOG"

  if grep -qE 'dependency\.complete|\[auto_deps\] DONE( |$)|\[auto_deps\] DONE scan-only|\[auto_deps\] DONE repair-log' "$AUTO_DEPS_LOG"; then
    core_ok dependency.check "auto_deps log contains DONE marker"
  else
    core_warn dependency.check "auto_deps log exists but no DONE marker found"
  fi
else
  core_warn dependency.check "auto_deps log not found yet; run auto_deps.py once to generate it: $AUTO_DEPS_LOG"
fi

if [ "$CHECK_FAILED" -eq 0 ]; then
  core_ok dependency.check "dependency layer self-check PASSED"
  exit 0
else
  record_failure "dependency layer self-check FAILED"
  exit 1
fi
