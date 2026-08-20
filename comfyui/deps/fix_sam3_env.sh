#!/usr/bin/env bash
set -euo pipefail

COMFYUI_ROOT="${EVERSPARK_COMFYUI_ROOT:-/root/ComfyUI}"
COMFY_ENV_WORKSPACE="${COMFY_ENV_WORKSPACE:-/root/.ce}"
SAM3_DIR="${SAM3_DIR:-${COMFYUI_ROOT}/custom_nodes/comfyui-sam3}"
SAM3_FALLBACK_CUDA="${SAM3_FALLBACK_CUDA:-12.4}"
SAM3_FALLBACK_TORCH="${SAM3_FALLBACK_TORCH:-2.5}"
SAM3_COMFY_KITCHEN_VERSION="${SAM3_COMFY_KITCHEN_VERSION:-0.2.10}"

export COMFY_ENV_ROOT="$COMFY_ENV_WORKSPACE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sam3-env] $*"
}

version_ge() {
  local actual="$1"
  local minimum="$2"
  local lowest

  lowest="$(printf '%s\n' "$actual" "$minimum" | sort -V | head -n 1)"
  [ "$lowest" = "$minimum" ]
}

detect_driver_cuda() {
  nvidia-smi 2>/dev/null \
    | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' \
    | head -n 1
}

resolve_sam3_metadata() {
  python - "$SAM3_DIR" "$COMFYUI_ROOT" <<'PY'
from importlib.metadata import version
from pathlib import Path
import sys

from comfy_env.environment import cache

plugin_dir = Path(sys.argv[1]).resolve()
comfyui_root = Path(sys.argv[2]).resolve()
config_path = plugin_dir / "nodes" / "comfy-env.toml"

env_name = cache.get_env_name(plugin_dir, config_path)
env_dir = cache.get_workspace_env_dir(comfyui_root, env_name)

if hasattr(cache, "get_env_manifest_dir"):
    install_hash = cache.get_env_manifest_dir(env_name, comfyui_root) / "install.hash"
else:
    install_hash = cache.get_workspace_dir(comfyui_root) / "install.hash"

print(env_name)
print(env_dir)
print(install_hash)
print(version("comfy-env"))
PY
}

pin_sam3_comfy_kitchen() {
  python - "$SAM3_CONFIG" "$SAM3_COMFY_KITCHEN_VERSION" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r'(?m)^(\s*comfy-kitchen\s*=\s*)["\'][^"\']*["\']\s*$'
)
replacement = rf'\1"=={version}"'
updated, count = pattern.subn(replacement, text, count=1)

if count != 1:
    raise SystemExit(
        f"could not pin comfy-kitchen in {path}: expected one declaration"
    )

if updated != text:
    path.write_text(updated, encoding="utf-8")
    print(f"[sam3-env] pinned isolated comfy-kitchen=={version}: {path}")
else:
    print(f"[sam3-env] isolated comfy-kitchen already pinned: {path}")
PY
}

verify_sam3_env() {
  local env_python="$SAM3_ENV/bin/python"

  [ -x "$env_python" ] || {
    log "[VERIFY] isolation python missing: $env_python"
    return 1
  }

  SAM3_EXPECT_TORCH="$SAM3_EXPECT_TORCH" \
  SAM3_EXPECT_CUDA="$SAM3_EXPECT_CUDA" \
  "$env_python" - <<'PY'
import importlib
import importlib.metadata
import os

import torch

expected_torch = os.environ["SAM3_EXPECT_TORCH"]
expected_cuda = os.environ["SAM3_EXPECT_CUDA"]
actual_torch = ".".join(torch.__version__.split("+", 1)[0].split(".")[:2])
actual_cuda = torch.version.cuda or ""

if actual_torch != expected_torch:
    raise SystemExit(
        f"SAM3 torch mismatch: expected {expected_torch}, got {torch.__version__}"
    )
if not actual_cuda.startswith(expected_cuda):
    raise SystemExit(
        f"SAM3 CUDA mismatch: expected {expected_cuda}, got {actual_cuda or 'none'}"
    )

for module in ("comfy_kitchen", "cc_torch", "torch_generic_nms", "flash_attn"):
    importlib.import_module(module)

print("[sam3-env] verify torch =", torch.__version__)
print("[sam3-env] verify cuda  =", actual_cuda)
print(
    "[sam3-env] verify comfy-kitchen =",
    importlib.metadata.version("comfy-kitchen"),
)
print("[sam3-env] verify CUDA extensions = OK")
PY
}

run_sam3_install() {
  SAM3_NODE_DIR="$SAM3_DIR" \
  SAM3_OVERRIDE_CUDA="$SAM3_OVERRIDE_CUDA" \
  SAM3_OVERRIDE_TORCH="$SAM3_OVERRIDE_TORCH" \
  python - <<'PY'
import os
from pathlib import Path

override_cuda = os.environ.get("SAM3_OVERRIDE_CUDA", "")
override_torch = os.environ.get("SAM3_OVERRIDE_TORCH", "")

if override_cuda and override_torch:
    import comfy_env.packages.cuda_wheels as cuda_wheels

    combo = (override_cuda, override_torch)
    cuda_wheels.FALLBACK_COMBO = combo
    cuda_wheels.CUDA_TORCH_MAP[override_cuda] = override_torch

    registry = getattr(cuda_wheels, "WHEEL_INDEX_REGISTRY", None)
    if registry and "cuda" in registry:
        registry["cuda"]["fallback_combo"] = combo

    print(
        "[sam3-env] overriding comfy-env fallback combo:",
        f"cu{override_cuda.replace('.', '')}+torch{override_torch}",
    )

from comfy_env import install

install(node_dir=Path(os.environ["SAM3_NODE_DIR"]).resolve())
PY
}

if [ ! -d "$SAM3_DIR" ] && [ -d "${COMFYUI_ROOT}/custom_nodes/ComfyUI-SAM3" ]; then
  SAM3_DIR="${COMFYUI_ROOT}/custom_nodes/ComfyUI-SAM3"
fi

log "============================================================"
log "[STEP] comfyui-sam3 isolation env repair"
log "COMFYUI_ROOT=$COMFYUI_ROOT"
log "SAM3_DIR=$SAM3_DIR"
log "COMFY_ENV_ROOT=$COMFY_ENV_ROOT"
log "============================================================"

if [ ! -d "$SAM3_DIR" ]; then
  log "[SKIP] comfyui-sam3 not installed: $SAM3_DIR"
  exit 0
fi

SAM3_CONFIG="$SAM3_DIR/nodes/comfy-env.toml"

if [ ! -f "$SAM3_DIR/install.py" ]; then
  log "[ERROR] install.py not found: $SAM3_DIR/install.py"
  exit 1
fi

if [ ! -f "$SAM3_CONFIG" ]; then
  log "[ERROR] isolation config not found: $SAM3_CONFIG"
  exit 1
fi

if ! python -c 'import comfy_env' >/dev/null 2>&1; then
  log "[ERROR] comfy-env is not installed in the active ComfyUI environment"
  exit 1
fi

mapfile -t HOST_ABI < <(
  python - <<'PY'
import torch

print(".".join(torch.__version__.split("+", 1)[0].split(".")[:2]))
print(torch.version.cuda or "")
PY
)

HOST_TORCH_MINOR="${HOST_ABI[0]:-}"
HOST_TORCH_CUDA="${HOST_ABI[1]:-}"
SAM3_EXPECT_TORCH="$HOST_TORCH_MINOR"
SAM3_EXPECT_CUDA="$HOST_TORCH_CUDA"
SAM3_OVERRIDE_CUDA=""
SAM3_OVERRIDE_TORCH=""

if [ "$HOST_TORCH_MINOR" = "2.5" ] && [ "$HOST_TORCH_CUDA" = "12.1" ]; then
  DRIVER_CUDA="$(detect_driver_cuda)"

  if [ -z "$DRIVER_CUDA" ]; then
    log "[ERROR] cannot detect driver CUDA compatibility from nvidia-smi"
    exit 1
  fi

  if ! version_ge "$DRIVER_CUDA" "$SAM3_FALLBACK_CUDA"; then
    log "[ERROR] SAM3 requires driver CUDA >= $SAM3_FALLBACK_CUDA"
    log "[ERROR] detected driver CUDA compatibility: $DRIVER_CUDA"
    exit 1
  fi

  SAM3_OVERRIDE_CUDA="$SAM3_FALLBACK_CUDA"
  SAM3_OVERRIDE_TORCH="$SAM3_FALLBACK_TORCH"
  SAM3_EXPECT_CUDA="$SAM3_FALLBACK_CUDA"
  SAM3_EXPECT_TORCH="$SAM3_FALLBACK_TORCH"

  log "[INFO] cu121/torch2.5 lacks the complete SAM3 wheel set"
  log "[INFO] using isolated fallback: cu124 + torch2.5"
  log "[INFO] driver CUDA compatibility: $DRIVER_CUDA"

  pin_sam3_comfy_kitchen
fi

mapfile -t SAM3_META < <(resolve_sam3_metadata)
SAM3_ENV_NAME="${SAM3_META[0]:-}"
SAM3_ENV="${SAM3_ENV:-${SAM3_META[1]:-}}"
SAM3_INSTALL_HASH="${SAM3_META[2]:-}"
COMFY_ENV_VERSION="${SAM3_META[3]:-unknown}"

[ -n "$SAM3_ENV_NAME" ] || {
  log "[ERROR] comfy-env did not resolve an environment name"
  exit 1
}
[ -n "$SAM3_ENV" ] || {
  log "[ERROR] comfy-env did not resolve an environment path"
  exit 1
}

log "[INFO] host torch=$HOST_TORCH_MINOR cuda=$HOST_TORCH_CUDA"
log "[INFO] comfy-env=$COMFY_ENV_VERSION"
log "[INFO] SAM3_ENV_NAME=$SAM3_ENV_NAME"
log "[INFO] SAM3_ENV=$SAM3_ENV"
log "[INFO] expected isolated torch=$SAM3_EXPECT_TORCH cuda=$SAM3_EXPECT_CUDA"

if [ -d "$SAM3_ENV" ]; then
  if verify_sam3_env; then
    log "[OK] SAM3 isolation env is healthy"
    exit 0
  fi

  BROKEN_ENV="${SAM3_ENV}.broken-$(date '+%Y%m%d-%H%M%S')"
  log "[WARN] existing SAM3 env failed verification"
  log "[WARN] preserving it as: $BROKEN_ENV"
  mv "$SAM3_ENV" "$BROKEN_ENV"
fi

if [ -n "$SAM3_INSTALL_HASH" ] && [ -f "$SAM3_INSTALL_HASH" ]; then
  rm -f "$SAM3_INSTALL_HASH"
  log "[FIX] removed stale generated install hash: $SAM3_INSTALL_HASH"
fi

log "[RUN] building SAM3 isolation env"
run_sam3_install

if [ ! -d "$SAM3_ENV" ]; then
  log "[ERROR] comfy-env completed but isolation env is missing: $SAM3_ENV"
  exit 1
fi

if ! verify_sam3_env; then
  log "[ERROR] SAM3 isolation env was built but verification failed"
  exit 1
fi

log "[OK] SAM3 isolation env repaired and verified"
