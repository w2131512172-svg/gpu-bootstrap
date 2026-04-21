#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME:-torch251-cu121}"
PY_VER="${PY_VER:-3.10}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

export DEBIAN_FRONTEND=noninteractive

preflight_check() {

    # 1. 检查 /etc/os-release
    if [ ! -f /etc/os-release ]; then
        echo "[ERROR] Unsupported OS"
        exit 1
    fi

    # 2. 检查 uname
    UNAME=$(uname -a)

    echo "$UNAME" | grep -qi "linux" || {
        echo "[ERROR] Not a Linux system"
        exit 1
    }

    echo "$UNAME" | grep -qi "x86_64" || {
        echo "[ERROR] Unsupported architecture"
        exit 1
    }

    # 3. 检查 nvidia-smi
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "[ERROR] nvidia-smi not found"
        exit 1
    fi

    SMI_OUTPUT=$(nvidia-smi 2>/dev/null) || {
        echo "[ERROR] nvidia-smi failed"
        exit 1
    }

    # 提取 CUDA Version
    CUDA_VER=$(echo "$SMI_OUTPUT" | grep "CUDA Version" | awk '{for(i=1;i<=NF;i++) if($i=="Version:") print $(i+1)}')

    if [ -z "$CUDA_VER" ]; then
        echo "[ERROR] Cannot detect CUDA version"
        exit 1
    fi

    # 判断 CUDA >= 12.1
    REQUIRED=12.1

    # 用 awk 做浮点比较
    awk "BEGIN {exit !($CUDA_VER >= $REQUIRED)}" || {
        echo "[ERROR] CUDA too low: $CUDA_VER"
        exit 1
    }

}

preflight_check

echo "== [1/5] apt packages =="
apt-get update
apt-get install -y \
  git \
  wget \
  aria2 \
  ffmpeg \
  libgl1 \
  libglib2.0-0 \
  build-essential \
  ca-certificates \
  bzip2 \
  rclone \
  zip \
  unzip

echo "== [1.5/5] install cloudflared =="
if [ ! -x /usr/local/bin/cloudflared ]; then
  wget -O /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /tmp/cloudflared
mv /tmp/cloudflared /usr/local/bin/cloudflared
else
  echo "cloudflared already exists: /usr/local/bin/cloudflared"
fi

echo "== [2/5] ensure conda (miniconda) =="

# If conda isn't on PATH, but an installation directory exists, reuse it.
if ! command -v conda >/dev/null 2>&1; then
  if [ -x "${MINICONDA_DIR}/bin/conda" ]; then
    echo "conda not in PATH, but existing Miniconda found at: ${MINICONDA_DIR}"
    export PATH="${MINICONDA_DIR}/bin:${PATH}"
  else
    echo "conda not found, installing Miniconda to: ${MINICONDA_DIR}"
    mkdir -p /tmp/miniconda_install
    cd /tmp/miniconda_install

    wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-py310_24.1.2-0-Linux-x86_64.sh
    bash miniconda.sh -b -p "${MINICONDA_DIR}"
    rm -f miniconda.sh

    export PATH="${MINICONDA_DIR}/bin:${PATH}"
  fi
fi

echo "== [3/5] conda env =="
# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  conda create -y -n "$ENV_NAME" "python=${PY_VER}"
fi

conda activate "$ENV_NAME"

command -v nvidia-smi >/dev/null && nvidia-smi || echo "[WARN] nvidia-smi not found"

echo "== [4/5] pip install torch/cu121 + xformers =="
python -m pip install -U pip setuptools wheel

python -m pip install \
  --index-url https://download.pytorch.org/whl/cu121 \
  torch==2.5.1+cu121 \
  torchvision==0.20.1+cu121 \
  torchaudio==2.5.1+cu121

python -m pip install xformers==0.0.27.post2 --no-deps

python -m pip install tomli==2.0.1

echo "== [5/5] healthcheck =="
python - <<'PY'
import torch, torchvision, torchaudio, xformers, tomli
print("torch      =", torch.__version__)
print("torchvision=", torchvision.__version__)
print("torchaudio =", torchaudio.__version__)
print("xformers   =", xformers.__version__)
print("cuda avail =", torch.cuda.is_available())
print("cuda ver   =", torch.version.cuda)
print("tomli      =", tomli.__version__)
PY

# ====== Conda auto-init & auto-activate ======
echo "== [6/6] shell setup =="

"${MINICONDA_DIR}/bin/conda" init bash
"${MINICONDA_DIR}/bin/conda" config --set auto_activate_base false

if ! grep -q "conda activate ${ENV_NAME}" "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<EOF

# Auto-activate project env
if [ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]; then
  . "${MINICONDA_DIR}/etc/profile.d/conda.sh"
  conda activate ${ENV_NAME}
fi
EOF
fi

echo "DONE."
