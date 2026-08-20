#!/usr/bin/env bash
set -euo pipefail

COMFYUI_ROOT="${AI_FORGE_COMFYUI_ROOT:-/root/ComfyUI}"
COMFY_ENV_WORKSPACE="${COMFY_ENV_WORKSPACE:-/root/.ce}"
SAM3_DIR="${COMFYUI_ROOT}/custom_nodes/comfyui-sam3"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sam3-env] $*"
}

detect_sam3_abi() {
  python - <<'PY'
import sys

import torch

python_abi = f"py{sys.version_info.major}{sys.version_info.minor}"
torch_parts = torch.__version__.split("+", 1)[0].split(".")
if len(torch_parts) < 2:
    raise SystemExit(f"cannot derive Torch ABI from: {torch.__version__}")

cuda_version = torch.version.cuda
if not cuda_version:
    raise SystemExit("cannot derive CUDA ABI: torch.version.cuda is empty")

torch_abi = f"torch{torch_parts[0]}-{torch_parts[1]}"
cuda_abi = "cu" + cuda_version.replace(".", "")
print(f"{python_abi}-{torch_abi}-{cuda_abi}")
PY
}

SAM3_ABI="${SAM3_ABI:-$(detect_sam3_abi)}"
SAM3_ENV_NAME="${SAM3_ENV_NAME:-sam3-nodes-${SAM3_ABI}}"
SAM3_ENV="${SAM3_ENV:-${COMFY_ENV_WORKSPACE}/envs/${SAM3_ENV_NAME}/.pixi/envs/default}"

log "============================================================"
log "[STEP] comfyui-sam3 isolation env check"
log "COMFYUI_ROOT=$COMFYUI_ROOT"
log "SAM3_DIR=$SAM3_DIR"
log "SAM3_ABI=$SAM3_ABI"
log "SAM3_ENV_NAME=$SAM3_ENV_NAME"
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
  log "[ERROR] install.py completed but expected ABI env is still missing: $SAM3_ENV"
  exit 1
fi
