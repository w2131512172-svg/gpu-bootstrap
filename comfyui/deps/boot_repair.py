#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from scanner.scan_logs import scan_missing_modules
from rules.dedupe import dedupe_keep_order

SCRIPT_DIR = Path(__file__).resolve().parent
COMFYUI_DIR = SCRIPT_DIR.parent
START_ALL = COMFYUI_DIR / "start_all.sh"
AUTO_DEPS = SCRIPT_DIR / "auto_deps.py"

LOG_DIR = Path(os.environ.get("AI_FORGE_LOG_DIR", "/root/ai_forge_logs"))
SERVICE_LOG = Path(os.environ.get("SERVICE_LOG", str(LOG_DIR / "comfyui.log")))
BOOT_REPAIR_LOG = LOG_DIR / "boot_repair.log"

DEFAULT_READY_MARKER = "Starting server"
DEFAULT_TIMEOUT = int(os.environ.get("BOOT_REPAIR_TIMEOUT", "300"))
DEFAULT_POLL_INTERVAL = float(os.environ.get("BOOT_REPAIR_POLL_INTERVAL", "1"))
DEFAULT_MAX_ROUNDS = int(os.environ.get("BOOT_REPAIR_MAX_ROUNDS", "3"))


class Tee:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, data: str) -> None:
        for stream in self.streams:
            stream.write(data)
            stream.flush()

    def flush(self) -> None:
        for stream in self.streams:
            stream.flush()


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_fp = open(BOOT_REPAIR_LOG, "a", encoding="utf-8")
    sys.stdout = Tee(sys.__stdout__, log_fp)
    sys.stderr = Tee(sys.__stderr__, log_fp)
    print("=" * 60)
    print("[boot_repair] START:", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("[boot_repair] LOG:", BOOT_REPAIR_LOG)


def log(*parts: object) -> None:
    print("[boot_repair]", *parts)


def read_log_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="ignore")


def wait_for_ready_marker(log_path: Path, marker: str, timeout: int, poll_interval: float) -> bool:
    log("waiting for ready marker:", repr(marker))
    log("service log:", log_path)
    log("timeout:", timeout)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if marker in read_log_text(log_path):
            log("ready marker detected")
            return True
        time.sleep(poll_interval)
    log("ready marker not detected before timeout")
    return False


def run_cmd(cmd: list[str], *, check: bool = True) -> int:
    log("RUN:", " ".join(cmd))
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
    proc.wait()
    if check and proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return proc.returncode


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="EverForge ComfyUI first-boot ModuleNotFoundError repair pass"
    )
    parser.add_argument("--log", type=str, default=str(SERVICE_LOG))
    parser.add_argument("--marker", type=str, default=DEFAULT_READY_MARKER)
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--poll-interval", type=float, default=DEFAULT_POLL_INTERVAL)
    parser.add_argument("--max-rounds", type=int, default=DEFAULT_MAX_ROUNDS)
    parser.add_argument("--no-restart", action="store_true")
    parser.add_argument("--upgrade-tools", action="store_true")
    return parser.parse_args()


def run_repair_round(log_path: Path, args: argparse.Namespace, round_no: int, attempted: set[str]) -> bool:
    print("=" * 60)
    print(f"[boot_repair] repair round {round_no}/{args.max_rounds}")
    print("=" * 60)

    ready = wait_for_ready_marker(log_path, args.marker, args.timeout, args.poll_interval)
    if not ready:
        log("skip repair: ComfyUI ready marker was not found")
        return False

    modules = dedupe_keep_order(scan_missing_modules(log_path))
    log("ModuleNotFoundError modules:", len(modules))

    if not modules:
        log("no ModuleNotFoundError detected; nothing to repair")
        return False

    new_modules = [m for m in modules if m not in attempted]
    if not new_modules:
        log("detected modules were already attempted; stop repair")
        log("modules:", ", ".join(modules))
        return False

    print("=" * 60)
    print("[boot_repair] detected missing modules:")
    for module in modules:
        prefix = "+" if module in new_modules else "="
        print(f" {prefix} {module}")
    print("[boot_repair] starting repair pass")
    print("=" * 60)

    attempted.update(new_modules)

    repair_cmd = [
        sys.executable,
        str(AUTO_DEPS),
        "--repair-log",
        str(log_path),
        "--repair-install",
    ]
    if not args.upgrade_tools:
        repair_cmd.append("--no-upgrade-tools")

    run_cmd(repair_cmd)

    if args.no_restart:
        log("repair installed; restart skipped by --no-restart")
        return False

    log("restarting ComfyUI only via start_all.sh restart")
    run_cmd(["bash", str(START_ALL), "restart"])

    print("=" * 60)
    print("[boot_repair] repair pass complete")
    print("[boot_repair] ComfyUI restarted without touching Cloudflare Tunnel")
    print("=" * 60)
    return True


def main() -> None:
    setup_logging()
    args = parse_args()
    log_path = Path(args.log)

    if args.max_rounds < 1:
        raise SystemExit("--max-rounds must be >= 1")
    if not START_ALL.exists():
        raise SystemExit(f"start_all.sh not found: {START_ALL}")
    if not AUTO_DEPS.exists():
        raise SystemExit(f"auto_deps.py not found: {AUTO_DEPS}")

    attempted: set[str] = set()
    for round_no in range(1, args.max_rounds + 1):
        repaired = run_repair_round(log_path, args, round_no, attempted)
        if not repaired:
            log("DONE")
            return

    log("max repair rounds reached:", args.max_rounds)
    log("DONE")


if __name__ == "__main__":
    main()
