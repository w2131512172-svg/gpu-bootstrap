#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/system/apt.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/system/platform.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/hardware/gpu.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/network/cloudflared.sh"

# ============================================================
# AI Forge - Bootstrap V2 cu128 profile
# Responsibility:
#   Environment layer ONLY.
#
# Target:
#   CUDA 12.8+ / RTX 50-series / Blackwell sm_120.
#
# Notes:
#   - Installs PyTorch cu128 wheels.
#   - Does not install xformers by default. ComfyUI can fall back to
#     pytorch attention, which is safer for the first cu128 baseline.
# ============================================================

ENV_NAME="${ENV_NAME:-torch-cu128}"
PY_VER="${PY_VER:-3.10}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

REQUIRED_CUDA="${REQUIRED_CUDA:-12.8}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"

# Leave torch packages unpinned by default so the cu128 profile can follow
# PyTorch's current compatible cu128 wheel set. Set these env vars to pin.
TORCH_VERSION="${TORCH_VERSION:-}"
TORCHVISION_VERSION="${TORCHVISION_VERSION:-}"
TORCHAUDIO_VERSION="${TORCHAUDIO_VERSION:-}"
INSTALL_XFORMERS="${INSTALL_XFORMERS:-0}"
XFORMERS_VERSION="${XFORMERS_VERSION:-}"
TOMLI_VERSION="${TOMLI_VERSION:-2.0.1}"

BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-/root/ai_forge_bootstrap.log}"
BOOTSTRAP_ENV_INFO="${BOOTSTRAP_ENV_INFO:-/root/bootstrap_env_info.txt}"

export DEBIAN_FRONTEND=noninteractive

APT_PACKAGES=(
  git
  wget
  curl
  aria2
  ffmpeg
  libgl1
  libglib2.0-0
  build-essential
  ca-certificates
  bzip2
  rclone
  zip
  unzip
  lsof
  jq
)

CORE_LOG_FILE="$BOOTSTRAP_LOG"
export CORE_LOG_FILE

log() {
  core_info "$@"
}

die() {
  core_error "$@"
  exit 1
}

section() {
  core_section "$@"
}

preflight_check() {
  section "[1/8] preflight check"

  core_check_linux_x86_64
  core_gpu_require_nvidia_smi

  local cuda_ver
  cuda_ver="$(core_gpu_driver_cuda_version)"
  [ -n "$cuda_ver" ] || die "Cannot detect CUDA version from nvidia-smi"

  core_version_ge "$cuda_ver" "$REQUIRED_CUDA" \
    || die "CUDA too low: detected=$cuda_ver required>=$REQUIRED_CUDA"

  log "[OK] CUDA driver version detected: $cuda_ver"
}

install_apt_packages() {
  section "[2/8] apt packages"
  core_apt_install_missing "${APT_PACKAGES[@]}"
}

install_cloudflared() {
  section "[3/8] cloudflared"
  core_cloudflared_install
}

ensure_conda() {
  section "[4/8] ensure conda"

  if command -v conda >/dev/null 2>&1; then
    log "[OK] conda found: $(command -v conda)"
    return 0
  fi

  if [ -x "${MINICONDA_DIR}/bin/conda" ]; then
    log "[OK] existing Miniconda found: ${MINICONDA_DIR}"
    export PATH="${MINICONDA_DIR}/bin:${PATH}"
    return 0
  fi

  log "[INFO] installing Miniconda to: ${MINICONDA_DIR}"

  mkdir -p /tmp/miniconda_install
  pushd /tmp/miniconda_install >/dev/null

  wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-py310_24.1.2-0-Linux-x86_64.sh
  bash miniconda.sh -b -p "${MINICONDA_DIR}"
  rm -f miniconda.sh

  popd >/dev/null

  export PATH="${MINICONDA_DIR}/bin:${PATH}"
  log "[OK] Miniconda installed"
}

ensure_conda_env() {
  section "[5/8] conda env"

  # shellcheck disable=SC1091
  source "$(conda info --base)/etc/profile.d/conda.sh"

  conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
  conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

  if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    log "[OK] conda env already exists: $ENV_NAME"
  else
    log "[INFO] creating conda env: $ENV_NAME python=$PY_VER"
    conda create -y -n "$ENV_NAME" "python=${PY_VER}"
    log "[OK] conda env created: $ENV_NAME"
  fi

  conda activate "$ENV_NAME"
  log "[OK] conda env activated: $ENV_NAME"
  log "[INFO] python: $(python --version)"
}

install_torch_stack() {
  section "[6/8] torch stack"

  python -m pip install -U pip setuptools wheel

  log "[INFO] uninstalling old torch/xformers stack if present"
  python -m pip uninstall -y torch torchvision torchaudio xformers >/dev/null 2>&1 || true

  local torch_pkgs=(torch torchvision torchaudio)

  [ -n "$TORCH_VERSION" ] && torch_pkgs[0]="torch==${TORCH_VERSION}"
  [ -n "$TORCHVISION_VERSION" ] && torch_pkgs[1]="torchvision==${TORCHVISION_VERSION}"
  [ -n "$TORCHAUDIO_VERSION" ] && torch_pkgs[2]="torchaudio==${TORCHAUDIO_VERSION}"

  log "[INFO] installing torch stack from: $TORCH_INDEX_URL"
  python -m pip install --index-url "$TORCH_INDEX_URL" "${torch_pkgs[@]}"

  if [ "$INSTALL_XFORMERS" = "1" ]; then
    if [ -n "$XFORMERS_VERSION" ]; then
      log "[INFO] installing xformers=$XFORMERS_VERSION"
      python -m pip install "xformers==${XFORMERS_VERSION}"
    else
      log "[INFO] installing latest compatible xformers"
      python -m pip install xformers
    fi
  else
    log "[INFO] skipping xformers for cu128 profile; ComfyUI will use pytorch attention"
  fi

  python -m pip install "tomli==${TOMLI_VERSION}"

  log "[OK] torch stack ready"
}

run_healthcheck() {
  section "[7/8] healthcheck"

  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || log "[WARN] nvidia-smi not found"

  log "[INFO] ffmpeg: $(ffmpeg -version 2>/dev/null | head -n 1 || echo 'missing')"
  log "[INFO] rclone: $(rclone version 2>/dev/null | head -n 1 || echo 'missing')"
  log "[INFO] cloudflared: $(cloudflared --version 2>/dev/null || echo 'missing')"

  python - <<'PY'
import importlib.util
import torch, torchvision, torchaudio, tomli

print("torch      =", torch.__version__)
print("torchvision=", torchvision.__version__)
print("torchaudio =", torchaudio.__version__)
print("cuda avail =", torch.cuda.is_available())
print("cuda ver   =", torch.version.cuda)
print("tomli      =", tomli.__version__)

if importlib.util.find_spec("xformers"):
    import xformers
    print("xformers   =", xformers.__version__)
else:
    print("xformers   = not installed")

if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available in torch")

print("device     =", torch.cuda.get_device_name(0))
print("capability =", torch.cuda.get_device_capability(0))
x = torch.randn(1, device="cuda")
print("cuda tensor=", x)
PY

  log "[OK] healthcheck passed"
}

write_env_info() {
  section "[8/8] write env info"

  local cuda_driver torch_version torch_cuda torchvision_version torchaudio_version xformers_version
  cuda_driver="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' | head -n 1 || true)"
  torch_version="$(python - <<'PY' 2>/dev/null || true
import torch
print(torch.__version__)
PY
)"
  torch_cuda="$(python - <<'PY' 2>/dev/null || true
import torch
print(torch.version.cuda)
PY
)"
  torchvision_version="$(python - <<'PY' 2>/dev/null || true
import torchvision
print(torchvision.__version__)
PY
)"
  torchaudio_version="$(python - <<'PY' 2>/dev/null || true
import torchaudio
print(torchaudio.__version__)
PY
)"
  xformers_version="$(python - <<'PY' 2>/dev/null || true
try:
    import xformers
    print(xformers.__version__)
except Exception:
    print('not installed')
PY
)"

  cat > "$BOOTSTRAP_ENV_INFO" <<EOF
AI_FORGE_BOOTSTRAP_ENV_INFO
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

TORCH_PROFILE=cu128
ENV_NAME=${ENV_NAME}
PY_VER=${PY_VER}
MINICONDA_DIR=${MINICONDA_DIR}

CUDA_DRIVER=${cuda_driver}
REQUIRED_CUDA=${REQUIRED_CUDA}
TORCH_INDEX_URL=${TORCH_INDEX_URL}

TORCH_VERSION=${torch_version}
TORCH_CUDA=${torch_cuda}
TORCHVISION_VERSION=${torchvision_version}
TORCHAUDIO_VERSION=${torchaudio_version}
XFORMERS_VERSION=${xformers_version}
TOMLI_VERSION=${TOMLI_VERSION}

CLOUDFLARED_VERSION=$(cloudflared --version 2>/dev/null || echo "missing")
RCLONE_VERSION=$(rclone version 2>/dev/null | head -n 1 || echo "missing")
FFMPEG_VERSION=$(ffmpeg -version 2>/dev/null | head -n 1 || echo "missing")
EOF

  log "[OK] env info written: $BOOTSTRAP_ENV_INFO"
}

setup_shell_env() {
  section "[9/9] shell setup"

  bash "${SCRIPT_DIR}/environment.sh" cleanup
  log "[OK] terminal auto-activation disabled; use: everspark comfy shell"
}

main() {
  : > "$BOOTSTRAP_LOG"

  section "AI Forge Bootstrap V2 cu128 started"

  preflight_check
  install_apt_packages
  install_cloudflared
  ensure_conda
  ensure_conda_env
  install_torch_stack
  run_healthcheck
  write_env_info
  setup_shell_env

  section "AI Forge Bootstrap V2 cu128 completed"
  log "[OK] DONE."
}

main "$@"
