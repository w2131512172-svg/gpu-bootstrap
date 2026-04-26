#!/usr/bin/env bash
set -e

echo "[AI Forge] Bootstrap start..."

FORGE_ROOT="/root/ollama-forge"
DATA_ROOT="/root/ollama-forge-data"
VENV_DIR="$FORGE_ROOT/venv"

# ===== 基础工具 =====
apt update
apt install -y \
  curl wget git \
  ca-certificates \
  build-essential \
  net-tools iproute2 \
  htop tree nano \
  python3.11 python3.11-venv python3-pip \
  pciutils lshw \
  ffmpeg \
  unzip zip

# ===== rclone =====
if ! command -v rclone >/dev/null 2>&1; then
  echo "[AI Forge] Installing rclone..."
  curl https://rclone.org/install.sh | bash
else
  echo "[AI Forge] rclone already installed"
fi

# ===== cloudflared =====
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "[AI Forge] Installing cloudflared..."
  wget -O /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /usr/local/bin/cloudflared
else
  echo "[AI Forge] cloudflared already installed"
fi

# ===== Ollama =====
if ! command -v ollama >/dev/null 2>&1; then
  echo "[AI Forge] Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
else
  echo "[AI Forge] Ollama already installed"
fi

# ===== 目录结构 =====
echo "[AI Forge] Creating directories..."
mkdir -p "$DATA_ROOT/open-webui"
mkdir -p /root/.ollama
mkdir -p "$FORGE_ROOT/tunnel"

# ===== Python venv =====
if [ ! -d "$VENV_DIR" ]; then
  echo "[AI Forge] Creating Python venv..."
  python3.11 -m venv "$VENV_DIR"
else
  echo "[AI Forge] Python venv already exists"
fi

source "$VENV_DIR/bin/activate"

# ===== Open WebUI =====
echo "[AI Forge] Installing / updating Open WebUI..."
pip install --upgrade pip
pip install --upgrade open-webui

echo "[AI Forge] Bootstrap done."

echo
echo "[AI Forge] Versions:"
echo "ollama:      $(ollama --version 2>/dev/null || true)"
echo "rclone:      $(rclone version 2>/dev/null | head -1 || true)"
echo "cloudflared: $(cloudflared --version 2>/dev/null || true)"
echo "python:      $(python --version 2>/dev/null || true)"
echo "ffmpeg:      $(ffmpeg -version 2>/dev/null | head -1 || true)"
