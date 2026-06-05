#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
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
COMFYUI_ROOT = Path(os.environ.get("AI_FORGE_COMFYUI_ROOT", "/root/ComfyUI")).resolve()
CUSTOM_NODES = COMFYUI_ROOT / "custom_nodes"

OUT_CLEAN = SCRIPT_DIR / "custom_nodes.clean.txt"
OUT_SKIPPED = SCRIPT_DIR / "custom_nodes.skipped.txt"
MANUAL_REQUIREMENTS = SCRIPT_DIR / "manual_requirements.txt"
COMPAT_REQUIREMENTS = SCRIPT_DIR / "compat_requirements.txt"

LOG_DIR = Path("/root/ai_forge_logs")
LOG_FILE = LOG_DIR / "auto_deps.log"


class Tee:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, data):
        for stream in self.streams:
            stream.write(data)
            stream.flush()

    def flush(self):
        for stream in self.streams:
            stream.flush()


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    log_fp = open(LOG_FILE, "a", encoding="utf-8")

    sys.stdout = Tee(sys.__stdout__, log_fp)
    sys.stderr = Tee(sys.__stderr__, log_fp)

    print("=" * 60)
    print("[auto_deps] START:", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    print("[auto_deps] LOG:", LOG_FILE)


def log(*parts: object) -> None:
    print("[auto_deps]", *parts)


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
    print("=" * 60)
    print("[auto_deps] EverForge repair-log summary")
    print("[auto_deps] missing modules:", len(modules))

    if modules:
        print("[auto_deps] modules:")
        for module in modules:
            print(" -", module)

    print("[auto_deps] mapped pip packages:", len(packages))
    if packages:
        for pkg in packages:
            print(" +", pkg)

    if packages and installed:
        print("[auto_deps] status: repaired on this temporary Pod")
        print("[auto_deps] please solidify these packages later into:")
        print(f"[auto_deps] {MANUAL_REQUIREMENTS}")
    elif packages:
        print("[auto_deps] status: repair packages detected but not installed")
        print("[auto_deps] rerun with --repair-install to install them")
    else:
        print("[auto_deps] status: no ModuleNotFoundError repair package detected")

    print("=" * 60)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="AI Forge ComfyUI dependency orchestrator"
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
    setup_logging()

    args = parse_args()

    log("script:", SCRIPT_DIR)
    log("root:", COMFYUI_ROOT)
    log("python:", sys.executable)

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
        log("DONE repair-log")
        return

    if args.scan_only:
        log("mode: scan-only")
        rescan()
        log("DONE scan-only")
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

    log("DONE")


if __name__ == "__main__":
    main()
