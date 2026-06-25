#!/usr/bin/env bash
set -euo pipefail

COMFYUI_ROOT="${AI_FORGE_COMFYUI_ROOT:-/root/ComfyUI}"
COMFY_ENV_WORKSPACE="${COMFY_ENV_WORKSPACE:-/root/.ce}"
SAM3_DIR="${COMFYUI_ROOT}/custom_nodes/comfyui-sam3"
SAM3_ENV="${COMFY_ENV_WORKSPACE}/envs/sam3-nodes/.pixi/envs/default"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sam3-env] $*"
}

log "============================================================"
log "[STEP] comfyui-sam3 isolation env check"
log "COMFYUI_ROOT=$COMFYUI_ROOT"
log "SAM3_DIR=$SAM3_DIR"
log "SAM3_ENV=$SAM3_ENV"
log "============================================================"

if [ ! -d "$SAM3_DIR" ]; then
  log "[SKIP] comfyui-sam3 not installed: $SAM3_DIR"
  exit 0
fi

if [ -d "$SAM3_ENV" ]; then
  log "[OK] isolation env exists: $SAM3_ENV"
  exit 0
fi

if [ ! -f "$SAM3_DIR/install.py" ]; then
  log "[ERROR] install.py not found: $SAM3_DIR/install.py"
  exit 1
fi

if [ ! -f "$SAM3_DIR/comfy-env-root.toml" ] && [ ! -f "$SAM3_DIR/comfy-env.toml" ]; then
  log "[ERROR] comfy-env config not found in: $SAM3_DIR"
  exit 1
fi

log "[FIX] isolation env missing: $SAM3_ENV"
log "[RUN] cd $SAM3_DIR && python install.py"

cd "$SAM3_DIR"
python install.py

if [ -d "$SAM3_ENV" ]; then
  log "[OK] isolation env repaired: $SAM3_ENV"
else
  log "[ERROR] install.py completed but env still missing: $SAM3_ENV"
  exit 1
fi
