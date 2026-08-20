#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

from scanner.scan_logs import scan_missing_modules
from rules.dedupe import dedupe_keep_order

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(REPO_ROOT / "core" / "logging"))

from everspark_logging import EverSparkLogger, get_logger  # noqa: E402

COMFYUI_DIR = SCRIPT_DIR.parent
START_ALL = COMFYUI_DIR / "start_all.sh"
AUTO_DEPS = SCRIPT_DIR / "auto_deps.py"

LOG_DIR = Path(os.environ.get("EVERSPARK_LOG_DIR", "/root/everspark_logs"))
SERVICE_LOG = Path(os.environ.get("SERVICE_LOG", str(LOG_DIR / "comfyui.log")))
BOOT_REPAIR_LOG = LOG_DIR / "boot_repair.log"

DEFAULT_READY_MARKER = "Starting server"
DEFAULT_TIMEOUT = int(os.environ.get("BOOT_REPAIR_TIMEOUT", "300"))
DEFAULT_POLL_INTERVAL = float(os.environ.get("BOOT_REPAIR_POLL_INTERVAL", "1"))
DEFAULT_MAX_ROUNDS = int(os.environ.get("BOOT_REPAIR_MAX_ROUNDS", "3"))
LOGGER: EverSparkLogger | None = None


def setup_logging() -> EverSparkLogger:
    return get_logger("dependencies.boot_repair", BOOT_REPAIR_LOG)


def log(*parts: object) -> None:
    if LOGGER is None:
        raise RuntimeError("logger is not initialized")
    LOGGER.info("boot_repair.progress", " ".join(str(part) for part in parts))


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
    assert LOGGER is not None
    LOGGER.info(
        "command.start",
        "Starting repair subprocess",
        command=Path(cmd[0]).name,
    )
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
    LOGGER.info(
        "command.complete",
        "Repair subprocess completed",
        command=Path(cmd[0]).name,
        exit_code=proc.returncode,
    )
    if check and proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return proc.returncode


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="EverSpark Forge ComfyUI first-boot ModuleNotFoundError repair pass"
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
    assert LOGGER is not None
    LOGGER.info(
        "boot_repair.round.start",
        "Starting dependency repair round",
        round=round_no,
        max_rounds=args.max_rounds,
    )

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

    LOGGER.info(
        "boot_repair.modules.detected",
        "Missing modules detected",
        modules=modules,
        new_modules=new_modules,
    )

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

    LOGGER.ok(
        "boot_repair.round.complete",
        "Repair pass completed and ComfyUI restarted",
        round=round_no,
    )
    return True


def main() -> None:
    global LOGGER
    LOGGER = setup_logging()
    try:
        args = parse_args()
        log_path = Path(args.log)

        LOGGER.info(
            "boot_repair.start",
            "ComfyUI boot repair started",
            service_log=str(log_path),
            max_rounds=args.max_rounds,
        )

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
                LOGGER.ok("boot_repair.complete", "Boot repair completed")
                return

        LOGGER.warning(
            "boot_repair.max_rounds",
            "Maximum repair rounds reached",
            max_rounds=args.max_rounds,
        )
        LOGGER.ok("boot_repair.complete", "Boot repair completed")
    except SystemExit as exc:
        if exc.code not in (None, 0):
            LOGGER.error(
                "boot_repair.failed",
                "Boot repair stopped",
                exit_code=exc.code,
            )
        raise
    except Exception as exc:
        LOGGER.error(
            "boot_repair.failed",
            "Boot repair failed",
            error_type=type(exc).__name__,
            error=str(exc),
        )
        raise
    finally:
        LOGGER.close()


if __name__ == "__main__":
    main()
