#!/usr/bin/env bash
set -euo pipefail

# Ollama Forge system prerequisite entry.
# Core owns common apt capabilities.
# Ollama remains an Ollama Forge dependency.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/system/apt.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-${LOG_DIR}/bootstrap.log}"
core_log_init ollama.prerequisites "$BOOTSTRAP_LOG"

install_common_apt_packages() {
  local packages=(
    curl
    wget
    git
    ca-certificates
    build-essential
    net-tools
    iproute2
    htop
    tree
    nano
    pciutils
    lshw
    ffmpeg
    rclone
    unzip
    zip
    zstd
  )

  core_apt_install_missing "${packages[@]}"
}

install_ollama_if_missing() {
  if core_command_exists ollama; then
    core_ok ollama.available "Ollama is already installed" \
      "version=$(ollama --version 2>/dev/null || true)"
    return 0
  fi

  core_info ollama.install "Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
}

print_versions() {
  core_info tools.versions "Ollama Forge tool versions" \
    "curl=$(curl --version 2>/dev/null | head -n 1 || true)" \
    "wget=$(wget --version 2>/dev/null | head -n 1 || true)" \
    "git=$(git --version 2>/dev/null || true)" \
    "ffmpeg=$(ffmpeg -version 2>/dev/null | head -n 1 || true)" \
    "rclone=$(rclone version 2>/dev/null | head -n 1 || true)" \
    "ollama=$(ollama --version 2>/dev/null || true)"
}

main() {
  core_require_root
  install_common_apt_packages
  install_ollama_if_missing
  print_versions
  core_ok prerequisites.complete "Ollama Forge prerequisites are ready"
}

main "$@"
