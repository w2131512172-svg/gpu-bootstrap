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
# EverSpark Forge - Bootstrap V2
# Responsibility:
#   Environment layer ONLY.
#
# Does NOT:
#   - clone ComfyUI
#   - pull R2 assets
#   - install custom node deps
#   - start ComfyUI
#   - start Cloudflare Tunnel
# ============================================================

ENV_NAME="${ENV_NAME:-torch251-cu121}"
PY_VER="${PY_VER:-3.10}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

REQUIRED_CUDA="${REQUIRED_CUDA:-12.1}"

TORCH_VERSION="${TORCH_VERSION:-2.5.1+cu121}"
TORCHVISION_VERSION="${TORCHVISION_VERSION:-0.20.1+cu121}"
TORCHAUDIO_VERSION="${TORCHAUDIO_VERSION:-2.5.1+cu121}"
XFORMERS_VERSION="${XFORMERS_VERSION:-0.0.27.post2}"
TOMLI_VERSION="${TOMLI_VERSION:-2.0.1}"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-${LOG_DIR}/bootstrap.log}"
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
)

core_log_init comfyui.bootstrap "$BOOTSTRAP_LOG"

preflight_check() {
  core_info bootstrap.section "[1/8] preflight check"

  core_check_linux_x86_64
  core_gpu_require_nvidia_smi

  local cuda_ver
  cuda_ver="$(core_gpu_driver_cuda_version)"
  [ -n "$cuda_ver" ] || core_die bootstrap.failed "Cannot detect CUDA version from nvidia-smi"

  core_version_ge "$cuda_ver" "$REQUIRED_CUDA" \
    || core_die bootstrap.failed "CUDA too low: detected=$cuda_ver required>=$REQUIRED_CUDA"

  core_ok bootstrap.status "CUDA driver version detected: $cuda_ver"
}

install_apt_packages() {
  core_info bootstrap.section "[2/8] apt packages"
  core_apt_install_missing "${APT_PACKAGES[@]}"
}

install_cloudflared() {
  core_info bootstrap.section "[3/8] cloudflared"
  core_cloudflared_install
}

ensure_conda() {
  core_info bootstrap.section "[4/8] ensure conda"

  if command -v conda >/dev/null 2>&1; then
    core_ok bootstrap.status "conda found: $(command -v conda)"
    return 0
  fi

  if [ -x "${MINICONDA_DIR}/bin/conda" ]; then
    core_ok bootstrap.status "existing Miniconda found: ${MINICONDA_DIR}"
    export PATH="${MINICONDA_DIR}/bin:${PATH}"
    return 0
  fi

  core_info bootstrap.status "installing Miniconda to: ${MINICONDA_DIR}"

  mkdir -p /tmp/miniconda_install
  pushd /tmp/miniconda_install >/dev/null

  wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-py310_24.1.2-0-Linux-x86_64.sh
  bash miniconda.sh -b -p "${MINICONDA_DIR}"
  rm -f miniconda.sh

  popd >/dev/null

  export PATH="${MINICONDA_DIR}/bin:${PATH}"
  core_ok bootstrap.status "Miniconda installed"
}

ensure_conda_env() {
  core_info bootstrap.section "[5/8] conda env"

  # shellcheck disable=SC1091
  source "$(conda info --base)/etc/profile.d/conda.sh"

  conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
  conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

  if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    core_ok bootstrap.status "conda env already exists: $ENV_NAME"
  else
    core_info bootstrap.status "creating conda env: $ENV_NAME python=$PY_VER"
    conda create -y -n "$ENV_NAME" "python=${PY_VER}"
    core_ok bootstrap.status "conda env created: $ENV_NAME"
  fi

  conda activate "$ENV_NAME"
  core_ok bootstrap.status "conda env activated: $ENV_NAME"
  core_info bootstrap.status "python: $(python --version)"
}

install_torch_stack() {
  core_info bootstrap.section "[6/8] torch stack"

  python -m pip install -U pip setuptools wheel

  local current_torch=""
  current_torch="$(python - <<'PY' 2>/dev/null || true
try:
    import torch
    print(torch.__version__)
except Exception:
    pass
PY
)"

  if [ "$current_torch" = "$TORCH_VERSION" ]; then
    core_ok bootstrap.status "torch already matches: $current_torch"
  else
    core_info bootstrap.status "installing torch stack: torch=$TORCH_VERSION torchvision=$TORCHVISION_VERSION torchaudio=$TORCHAUDIO_VERSION"
    python -m pip install \
      --index-url https://download.pytorch.org/whl/cu121 \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "torchaudio==${TORCHAUDIO_VERSION}"
  fi

  local current_xformers=""
  current_xformers="$(python - <<'PY' 2>/dev/null || true
try:
    import xformers
    print(xformers.__version__)
except Exception:
    pass
PY
)"

  if [ "$current_xformers" = "$XFORMERS_VERSION" ]; then
    core_ok bootstrap.status "xformers already matches: $current_xformers"
  else
    core_info bootstrap.status "installing xformers=$XFORMERS_VERSION"
    python -m pip install "xformers==${XFORMERS_VERSION}" --no-deps
  fi

  python -m pip install "tomli==${TOMLI_VERSION}"

  core_ok bootstrap.status "torch stack ready"
}

run_healthcheck() {
  core_info bootstrap.section "[7/8] healthcheck"

  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || core_warn bootstrap.status "nvidia-smi not found"

  core_info bootstrap.status "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n 1 || echo 'missing')"
  core_info bootstrap.status "rclone: $(rclone version 2>/dev/null | head -n 1 || echo 'missing')"
  core_info bootstrap.status "cloudflared: $(cloudflared --version 2>/dev/null || echo 'missing')"

  python - <<'PY'
import torch, torchvision, torchaudio, xformers, tomli

print("torch      =", torch.__version__)
print("torchvision=", torchvision.__version__)
print("torchaudio =", torchaudio.__version__)
print("xformers   =", xformers.__version__)
print("cuda avail =", torch.cuda.is_available())
print("cuda ver   =", torch.version.cuda)
print("tomli      =", tomli.__version__)

if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available in torch")
PY

  core_ok bootstrap.status "healthcheck passed"
}

write_env_info() {
  core_info bootstrap.section "[8/8] write env info"

  local cuda_driver
  cuda_driver="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' | head -n 1 || true)"

  cat > "$BOOTSTRAP_ENV_INFO" <<EOF
EVERSPARK_BOOTSTRAP_ENV_INFO
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

ENV_NAME=${ENV_NAME}
PY_VER=${PY_VER}
MINICONDA_DIR=${MINICONDA_DIR}

CUDA_DRIVER=${cuda_driver}
REQUIRED_CUDA=${REQUIRED_CUDA}

TORCH_VERSION=${TORCH_VERSION}
TORCHVISION_VERSION=${TORCHVISION_VERSION}
TORCHAUDIO_VERSION=${TORCHAUDIO_VERSION}
XFORMERS_VERSION=${XFORMERS_VERSION}
TOMLI_VERSION=${TOMLI_VERSION}

CLOUDFLARED_VERSION=$(cloudflared --version 2>/dev/null || echo "missing")
RCLONE_VERSION=$(rclone version 2>/dev/null | head -n 1 || echo "missing")
FFMPEG_VERSION=$(ffmpeg -version 2>/dev/null | head -n 1 || echo "missing")
EOF

  core_ok bootstrap.status "env info written: $BOOTSTRAP_ENV_INFO"
}

setup_shell_env() {
  core_info bootstrap.section "[9/9] shell setup"

  bash "${SCRIPT_DIR}/environment.sh" cleanup
  core_ok bootstrap.status "terminal auto-activation disabled; use: everspark comfy shell"
}

main() {
  : > "$BOOTSTRAP_LOG"

  core_info bootstrap.section "EverSpark Forge Bootstrap V2 started"

  preflight_check
  install_apt_packages
  install_cloudflared
  ensure_conda
  ensure_conda_env
  install_torch_stack
  run_healthcheck
  write_env_info
  setup_shell_env

  core_info bootstrap.section "EverSpark Forge Bootstrap V2 completed"
  core_ok bootstrap.status "DONE."
}

main "$@"
