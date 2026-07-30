#!/usr/bin/env bash

# Common host platform checks.

_CORE_SYSTEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${_CORE_SYSTEM_ROOT}/logging/log.sh"

core_check_linux_x86_64() {
  if [ ! -f /etc/os-release ]; then
    core_die "Unsupported OS: /etc/os-release is missing."
    return 1
  fi

  if [ "$(uname -s)" != "Linux" ]; then
    core_die "Unsupported operating system: $(uname -s)"
    return 1
  fi

  case "$(uname -m)" in
    x86_64|amd64)
      ;;
    *)
      core_die "Unsupported architecture: $(uname -m)"
      return 1
      ;;
  esac

  core_ok "Linux x86_64 detected."
}
