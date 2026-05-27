#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# AI Forge - Bootstrap V2 cu121 profile
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
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$BOOTSTRAP_LOG"
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

preflight_check() {
  section "[1/8] preflight check"

  [ -f /etc/os-release ] || die "Unsupported OS: /etc/os-release missing"

  local uname_out
  uname_out="$(uname -a)"
  echo "$uname_out" | grep -qi "linux" || die "Not a Linux system"
  echo "$uname_out" | grep -qi "x86_64" || die "Unsupported architecture: expected x86_64"

  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not found"

  local smi_output cuda_ver
  smi_output="$(nvidia-smi 2>/dev/null)" || die "nvidia-smi failed"
  cuda_ver="$(echo "$smi_output" | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p')"

  [ -n "$cuda_ver" ] || die "Cannot detect CUDA version from nvidia-smi"

  awk "BEGIN {exit !(\$cuda_ver >= \$REQUIRED_CUDA)}" || die "CUDA too low: detected=$cuda_ver required>=$REQUIRED_CUDA"

  log "[OK] Linux x86_64 detected"
  log "[OK] CUDA driver version detected: $cuda_ver"
}

install_apt_packages() {
  section "[2/8] apt packages"

  apt-get update
  apt-get install -y "${APT_PACKAGES[@]}"

  log "[OK] apt packages installed"
}

install_cloudflared() {
  section "[3/8] cloudflared"

  if [ -x /usr/local/bin/cloudflared ]; then
    log "[OK] cloudflared already exists: $(/usr/local/bin/cloudflared --version || true)"
    return 0
  fi

  log "[INFO] installing cloudflared to /usr/local/bin/cloudflared"
  wget -O /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /tmp/cloudflared
  mv /tmp/cloudflared /usr/local/bin/cloudflared

  log "[OK] cloudflared installed: $(cloudflared --version || true)"
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
    log "[OK] torch already matches: $current_torch"
  else
    log "[INFO] installing torch stack: torch=$TORCH_VERSION torchvision=$TORCHVISION_VERSION torchaudio=$TORCHAUDIO_VERSION"
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
    log "[OK] xformers already matches: $current_xformers"
  else
    log "[INFO] installing xformers=$XFORMERS_VERSION"
    python -m pip install "xformers==${XFORMERS_VERSION}" --no-deps
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

  log "[OK] healthcheck passed"
}

write_env_info() {
  section "[8/8] write env info"

  local cuda_driver
  cuda_driver="$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' | head -n 1 || true)"

  cat > "$BOOTSTRAP_ENV_INFO" <<EOF
AI_FORGE_BOOTSTRAP_ENV_INFO
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

TORCH_PROFILE=cu121
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

  log "[OK] env info written: $BOOTSTRAP_ENV_INFO"
}

setup_shell_env() {
  section "[9/9] shell setup"

  "${MINICONDA_DIR}/bin/conda" init bash
  "${MINICONDA_DIR}/bin/conda" config --set auto_activate_base false

  if ! grep -q "conda activate ${ENV_NAME}" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" <<EOF

# Auto-activate AI Forge project env
if [ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]; then
  . "${MINICONDA_DIR}/etc/profile.d/conda.sh"
  conda activate ${ENV_NAME}
fi
EOF
    log "[OK] auto-activate block added to ~/.bashrc"
  else
    log "[OK] auto-activate block already exists in ~/.bashrc"
  fi
}

main() {
  : > "$BOOTSTRAP_LOG"

  section "AI Forge Bootstrap V2 cu121 started"

  preflight_check
  install_apt_packages
  install_cloudflared
  ensure_conda
  ensure_conda_env
  install_torch_stack
  run_healthcheck
  write_env_info
  setup_shell_env

  section "AI Forge Bootstrap V2 cu121 completed"
  log "[OK] DONE."
}

main "$@"
