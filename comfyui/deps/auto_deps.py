#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from scanner.scan_requirements import scan_requirements
from scanner.scan_logs import scan_missing_modules
from rules.normalize import normalize_lines
from rules.dedupe import dedupe_keep_order
from rules.filter import split_clean_skipped
from rules.classify import split_normal_git
from rules.repair import repair_from_modules
from installer.runner import install_all, install_comfyui_requirements


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(REPO_ROOT / "core" / "logging"))

from everspark_logging import EverSparkLogger, get_logger  # noqa: E402

COMFYUI_ROOT = Path(os.environ.get("EVERSPARK_COMFYUI_ROOT", "/root/ComfyUI")).resolve()
CUSTOM_NODES = COMFYUI_ROOT / "custom_nodes"

OUT_CLEAN = SCRIPT_DIR / "custom_nodes.clean.txt"
OUT_SKIPPED = SCRIPT_DIR / "custom_nodes.skipped.txt"
MANUAL_REQUIREMENTS = SCRIPT_DIR / "manual_requirements.txt"
COMPAT_REQUIREMENTS = SCRIPT_DIR / "compat_requirements.txt"

LOG_DIR = Path(os.environ.get("EVERSPARK_LOG_DIR", "/root/everspark_logs"))
LOG_FILE = LOG_DIR / "auto_deps.log"
LOGGER: EverSparkLogger | None = None


def setup_logging() -> EverSparkLogger:
    return get_logger("dependencies.auto", LOG_FILE)


def log(*parts: object) -> None:
    if LOGGER is None:
        raise RuntimeError("logger is not initialized")
    LOGGER.info("dependency.progress", " ".join(str(part) for part in parts))


def read_requirements_file(path: Path) -> list[str]:
    if not path.exists():
        return []

    out: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        out.append(line)
    return out


def write_lines(path: Path, lines: list[str]) -> None:
    path.write_text(
        "\n".join(lines) + ("\n" if lines else ""),
        encoding="utf-8",
    )


def rescan() -> tuple[list[str], list[str]]:
    if not CUSTOM_NODES.exists():
        raise SystemExit(f"custom_nodes not found: {CUSTOM_NODES}")

    rows = scan_requirements(CUSTOM_NODES)
    lines = normalize_lines(rows)
    lines = dedupe_keep_order(lines)

    clean, skipped = split_clean_skipped(lines)

    write_lines(OUT_CLEAN, clean)
    write_lines(OUT_SKIPPED, skipped)

    log("root:", COMFYUI_ROOT)
    log("raw lines:", len(rows))
    log("clean lines:", len(clean))
    log("skipped lines:", len(skipped))
    log("wrote:", OUT_CLEAN)
    log("wrote:", OUT_SKIPPED)

    return clean, skipped


def load_existing_clean() -> list[str]:
    clean = read_requirements_file(OUT_CLEAN)
    if not clean:
        log("existing clean not found or empty, running rescan")
        clean, _ = rescan()
    else:
        log("using existing clean:", OUT_CLEAN)
        log("clean lines:", len(clean))

    return clean


def build_install_plan(clean: list[str]) -> tuple[list[str], list[str]]:
    manual = read_requirements_file(MANUAL_REQUIREMENTS)
    if manual:
        log("manual lines:", len(manual))
    else:
        log("manual requirements not found or empty:", MANUAL_REQUIREMENTS)

    compat = read_requirements_file(COMPAT_REQUIREMENTS)
    if compat:
        log("compat lines:", len(compat))
    else:
        log("compat requirements not found or empty:", COMPAT_REQUIREMENTS)

    merged = dedupe_keep_order(clean + manual + compat)
    normal, git = split_normal_git(merged)

    log("install plan normal:", len(normal))
    log("install plan git:", len(git))

    return normal, git


def print_repair_summary(modules: list[str], packages: list[str], *, installed: bool) -> None:
    if packages and installed:
        status = "installed"
    elif packages:
        status = "detected"
    else:
        status = "not_needed"

    assert LOGGER is not None
    LOGGER.info(
        "dependency.repair.summary",
        "Dependency repair summary",
        missing_modules=modules,
        packages=packages,
        status=status,
        manual_requirements=str(MANUAL_REQUIREMENTS),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="EverSpark Forge ComfyUI dependency orchestrator"
    )
    parser.add_argument(
        "--rescan",
        action="store_true",
        help="Scan custom_nodes and overwrite clean/skipped before installing.",
    )
    parser.add_argument(
        "--scan-only",
        action="store_true",
        help="Only scan custom_nodes and write clean/skipped. Do not install.",
    )
    parser.add_argument(
        "--no-upgrade-tools",
        action="store_true",
        help="Do not upgrade pip/setuptools/wheel before installing.",
    )
    parser.add_argument(
        "--repair-log",
        type=str,
        help="Parse ComfyUI log and map ModuleNotFoundError modules to pip packages.",
    )
    parser.add_argument(
        "--repair-install",
        action="store_true",
        help="Install only the packages detected from --repair-log.",
    )
    return parser.parse_args()


def main() -> None:
    global LOGGER
    LOGGER = setup_logging()

    try:
        args = parse_args()

        LOGGER.info(
            "dependency.start",
            "Dependency orchestration started",
            script=str(SCRIPT_DIR),
            root=str(COMFYUI_ROOT),
            python=sys.executable,
        )

        if args.repair_log:
            log_path = Path(args.repair_log)
            log("mode: repair-log")
            log("repair-log:", log_path)

            modules = dedupe_keep_order(scan_missing_modules(log_path))
            log("missing modules:", len(modules))

            packages = repair_from_modules(modules)
            packages = dedupe_keep_order(packages)
            log("repair packages:", len(packages))

            installed = False

            if args.repair_install:
                if packages:
                    log("installing repair packages only")
                    normal, git = split_normal_git(packages)
                    install_all(
                        normal,
                        git,
                        upgrade_tools=not args.no_upgrade_tools,
                    )
                    installed = True
                else:
                    log("no repair packages to install")

            print_repair_summary(modules, packages, installed=installed)
            LOGGER.ok("dependency.complete", "Dependency repair-log mode completed", mode="repair-log")
            return

        if args.scan_only:
            log("mode: scan-only")
            rescan()
            LOGGER.ok("dependency.complete", "Dependency scan completed", mode="scan-only")
            return

        if args.rescan:
            log("mode: rescan")
            clean, _ = rescan()
        else:
            log("mode: default")
            clean = load_existing_clean()

        normal, git = build_install_plan(clean)

        install_comfyui_requirements(COMFYUI_ROOT)

        install_all(
            normal,
            git,
            upgrade_tools=not args.no_upgrade_tools,
        )

        LOGGER.ok("dependency.complete", "Dependency installation completed", mode="default")
    except SystemExit as exc:
        if exc.code not in (None, 0):
            LOGGER.error(
                "dependency.failed",
                "Dependency orchestration stopped",
                exit_code=exc.code,
            )
        raise
    except Exception as exc:
        LOGGER.error(
            "dependency.failed",
            "Dependency orchestration failed",
            error_type=type(exc).__name__,
            error=str(exc),
        )
        raise
    finally:
        LOGGER.close()


if __name__ == "__main__":
    main()
