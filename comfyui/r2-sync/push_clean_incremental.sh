#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

CLEAN_SCRIPT="$SCRIPT_DIR/clean_local_junk.sh"
PUSH_SCRIPT="$SCRIPT_DIR/push_incremental.sh"

[ -f "$CLEAN_SCRIPT" ] || { echo "[ERROR] clean script not found: $CLEAN_SCRIPT"; exit 1; }
[ -f "$PUSH_SCRIPT" ] || { echo "[ERROR] push script not found: $PUSH_SCRIPT"; exit 1; }

echo "============================================================"
echo "[INFO] EverSpark Forge clean incremental push started"
echo "[INFO] SCRIPT_DIR=$SCRIPT_DIR"
if [ "$DRY_RUN" = true ]; then
  echo "[INFO] DRY RUN MODE ENABLED"
fi
echo "============================================================"

echo "[1/2] Cleaning local ComfyUI junk..."
if [ "$DRY_RUN" = true ]; then
  bash "$CLEAN_SCRIPT" --dry-run
else
  bash "$CLEAN_SCRIPT"
fi

echo "[2/2] Running incremental R2 push..."
if [ "$DRY_RUN" = true ]; then
  bash "$PUSH_SCRIPT" --dry-run
else
  bash "$PUSH_SCRIPT"
fi

echo "============================================================"
echo "[OK] EverSpark Forge clean incremental push completed"
echo "============================================================"
