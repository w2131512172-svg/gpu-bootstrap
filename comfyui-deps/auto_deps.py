#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from importlib import metadata
from pathlib import Path
from typing import Iterable

# Python 3.11: tomllib
# Python 3.10: tomli
try:
    import tomllib  # type: ignore[attr-defined]
except ModuleNotFoundError:
    tomllib = None  # type: ignore[assignment]

try:
    import tomli  # type: ignore[import-not-found]
except ModuleNotFoundError:
    tomli = None  # type: ignore[assignment]


BASE = Path(__file__).resolve().parent
CUSTOM_NODES = BASE / "custom_nodes"
DEPS_DIR = BASE / "deps"

OUT_CLEAN = DEPS_DIR / "custom_nodes.clean.txt"
OUT_SKIPPED = DEPS_DIR / "custom_nodes.skipped.txt"
OUT_AUDIT = DEPS_DIR / "audit.missing.txt"

REQ_FILENAMES = (
    "requirements.txt",
    "requirements-dev.txt",
    "requirements_extra.txt",
)

REQ_GLOBS = (
    "**/requirements*.txt",
    "**/pyproject.toml",
    "**/setup.py",
    "**/setup.cfg",
)

NAME_SEP_RE = re.compile(r"[-_.]+")
REQ_NAME_RE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)")

SKIP_PACKAGES = {
    "torch",
    "torchvision",
    "torchaudio",
    "xformers",
}

EXTRA_RUNTIME_DEPS = [
    "torchsde",
    "spandrel",
    "kornia",
    "mmcv-lite",
]

SKIP_EXACT_LINES = {
    "",
}

SKIP_LINE_PATTERNS = [
    re.compile(r"(^|\s)torch([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)torchvision([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)torchaudio([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)xformers([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"mmcv.*piwheels", re.IGNORECASE),
    re.compile(r"triton.*windows", re.IGNORECASE),
    re.compile(r"win_amd64\.whl", re.IGNORECASE),
]

INSTALL_UPGRADE_TOOLS = [sys.executable, "-m", "pip", "install", "-U", "pip", "setuptools", "wheel"]


def log(*parts: object) -> None:
    print("[auto_deps]", *parts)


def audit_log(*parts: object) -> None:
    print("[audit]", *parts)


def ensure_dirs() -> None:
    DEPS_DIR.mkdir(parents=True, exist_ok=True)


def canonicalize_name(name: str) -> str:
    return NAME_SEP_RE.sub("-", name).strip().lower()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def iter_dep_files() -> list[Path]:
    found: set[Path] = set()
    for pattern in REQ_GLOBS:
        for path in CUSTOM_NODES.glob(pattern):
            if path.is_file():
                found.add(path.resolve())
    return sorted(found)


def should_skip_line(line: str) -> tuple[bool, str]:
    raw = line.strip()

    if raw in SKIP_EXACT_LINES:
        return True, "empty"

    if raw.startswith("#"):
        return True, "comment"

    for pattern in SKIP_LINE_PATTERNS:
        if pattern.search(raw):
            return True, f"pattern:{pattern.pattern}"

    return False, ""


def normalize_requirement_line(line: str) -> str | None:
    raw = line.strip()
    if not raw:
        return None

    if " #" in raw:
        raw = raw.split(" #", 1)[0].strip()

    return raw or None


def parse_requirements_txt(path: Path) -> tuple[list[str], list[str]]:
    clean: list[str] = []
    skipped: list[str] = []

    for raw_line in read_text(path).splitlines():
        line = normalize_requirement_line(raw_line)
        if not line:
            continue

        skip, reason = should_skip_line(line)
        rel = path.relative_to(BASE)

        if skip:
            skipped.append(f"{rel} :: {line}    [skip:{reason}]")
            continue

        clean.append(line)

    return clean, skipped


def dedupe_keep_order(lines: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []

    for line in lines:
        key = line.strip()
        if not key:
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(key)

    return out


def is_git_requirement(line: str) -> bool:
    lowered = line.strip().lower()
    return lowered.startswith("git+") or " git+" in lowered


def is_skip_link(line: str) -> bool:
    skip, _ = should_skip_line(line)
    return skip


def is_pinned(line: str) -> bool:
    name = extract_req_name(line)
    if not name:
        return False
    return name in SKIP_PACKAGES


def scan_and_write() -> tuple[list[str], list[str]]:
    ensure_dirs()

    all_clean: list[str] = []
    all_skipped: list[str] = []

    for path in iter_dep_files():
        # 当前安装流程：只解析 requirements*.txt
        if path.name.startswith("requirements") and path.suffix == ".txt":
            clean, skipped = parse_requirements_txt(path)
            all_clean.extend(clean)
            all_skipped.extend(skipped)

    clean_final = dedupe_keep_order(all_clean)
    skipped_final = dedupe_keep_order(all_skipped)

    OUT_CLEAN.write_text(
        "\n".join(clean_final) + ("\n" if clean_final else ""),
        encoding="utf-8",
    )
    OUT_SKIPPED.write_text(
        "\n".join(skipped_final) + ("\n" if skipped_final else ""),
        encoding="utf-8",
    )

    return clean_final, skipped_final


def run_cmd(cmd: list[str], *, check: bool = True) -> int:
    log("RUN:", " ".join(cmd))
    proc = subprocess.run(cmd)
    if check and proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return proc.returncode


def install_requirements_file(path: Path) -> None:
    if not path.exists():
        return
    run_cmd([sys.executable, "-m", "pip", "install", "-r", str(path)])


def install_lines(lines: list[str]) -> None:
    normal_lines = [x for x in lines if not is_git_requirement(x)]
    git_lines = [x for x in lines if is_git_requirement(x)]

    if normal_lines:
        log(f"install normal deps: {len(normal_lines)}")
        run_cmd([sys.executable, "-m", "pip", "install", *normal_lines])

    for line in git_lines:
        log("install git dep:", line)
        run_cmd([sys.executable, "-m", "pip", "install", "--no-build-isolation", line])


def install(lines: list[str]) -> None:
    log("upgrade packaging tools")
    run_cmd(INSTALL_UPGRADE_TOOLS)

    root_requirements = BASE / "requirements.txt"
    if root_requirements.exists():
        log("install root requirements:", root_requirements)
        install_requirements_file(root_requirements)

    log("install extra runtime deps:", EXTRA_RUNTIME_DEPS)
    run_cmd([sys.executable, "-m", "pip", "install", *EXTRA_RUNTIME_DEPS])

    install_lines(lines)


def get_toml_module():
    if tomllib is not None:
        return tomllib
    if tomli is not None:
        return tomli
    return None


def extract_req_name(line: str) -> str | None:
    text = line.strip()
    if not text:
        return None

    lowered = text.lower()

    # 跳过注释
    if text.startswith("#"):
        return None

    # 跳过 URL / VCS / editable / 本地路径
    if lowered.startswith(("git+", "http://", "https://", "-e ", "--editable ")):
        return None
    if text.startswith((".", "/", "~")):
        return None

    # 处理 "name @ url"
    if " @ " in text:
        left = text.split(" @ ", 1)[0].strip()
        if left:
            return canonicalize_name(left)

    # 去掉环境标记
    if ";" in text:
        text = text.split(";", 1)[0].strip()

    match = REQ_NAME_RE.match(text)
    if not match:
        return None

    name = match.group(1)
    if "[" in name:
        name = name.split("[", 1)[0]

    return canonicalize_name(name)


def parse_pyproject_toml(path: Path, include_optional: bool = False) -> list[str]:
    mod = get_toml_module()
    if mod is None:
        audit_log("WARN: pyproject audit needs tomli on Python 3.10.x, skip:", path.relative_to(BASE))
        return []

    try:
        data = mod.loads(read_text(path))
    except Exception as exc:
        audit_log("WARN: failed to parse", path.relative_to(BASE), "->", exc)
        return []

    if not isinstance(data, dict):
        return []

    project = data.get("project")
    if not isinstance(project, dict):
        return []

    deps: list[str] = []

    raw_deps = project.get("dependencies", [])
    if isinstance(raw_deps, list):
        for item in raw_deps:
            if isinstance(item, str) and item.strip():
                deps.append(item.strip())

    if include_optional:
        optional = project.get("optional-dependencies", {})
        if isinstance(optional, dict):
            for _, group_items in optional.items():
                if isinstance(group_items, list):
                    for item in group_items:
                        if isinstance(item, str) and item.strip():
                            deps.append(item.strip())

    return deps


def get_installed_packages() -> set[str]:
    installed: set[str] = set()

    try:
        for dist in metadata.distributions():
            name = dist.metadata.get("Name")
            if not name:
                continue
            installed.add(canonicalize_name(name))
    except Exception as exc:
        audit_log("WARN: failed to enumerate installed packages ->", exc)

    return installed


def audit_pyproject(include_optional: bool = False) -> list[str]:
    ensure_dirs()

    pyprojects = [p for p in iter_dep_files() if p.name == "pyproject.toml"]
    if not pyprojects:
        OUT_AUDIT.write_text("", encoding="utf-8")
        return []

    installed = get_installed_packages()
    missing_lines: list[str] = []
    seen: set[tuple[str, str]] = set()

    for pyproject in pyprojects:
        rel = pyproject.relative_to(BASE)
        deps = parse_pyproject_toml(pyproject, include_optional=include_optional)

        for raw_dep in deps:
            dep_line = raw_dep.strip()
            if not dep_line:
                continue

            if is_skip_link(dep_line):
                continue

            pkg_name = extract_req_name(dep_line)
            if not pkg_name:
                continue

            if pkg_name in SKIP_PACKAGES:
                continue

            if pkg_name in installed:
                continue

            key = (str(rel), pkg_name)
            if key in seen:
                continue
            seen.add(key)

            missing_lines.append(f"{rel} :: {dep_line}")

    missing_lines = dedupe_keep_order(missing_lines)

    OUT_AUDIT.write_text(
        "\n".join(missing_lines) + ("\n" if missing_lines else ""),
        encoding="utf-8",
    )
    return missing_lines


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="ComfyUI custom_nodes dependency installer + pyproject audit"
    )
    parser.add_argument(
        "--audit",
        action="store_true",
        help="Only audit pyproject.toml dependencies. Do not install anything.",
    )
    parser.add_argument(
        "--include-optional",
        action="store_true",
        help="Include [project.optional-dependencies] in audit mode.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    log("root:", BASE)

    if not CUSTOM_NODES.exists():
        raise SystemExit("custom_nodes not found")

    if args.audit:
        missing = audit_pyproject(include_optional=args.include_optional)
        audit_log("wrote:", OUT_AUDIT)
        audit_log("missing deps:", len(missing))

        if missing:
            for item in missing:
                print(" -", item)
        else:
            audit_log("no missing deps found in pyproject.toml")

        return

    clean, skipped = scan_and_write()

    log("clean lines:", len(clean))
    log("skipped lines:", len(skipped))
    log("wrote:", OUT_CLEAN)
    log("wrote:", OUT_SKIPPED)

    if not clean:
        log("no installable custom_nodes requirements found")
        return

    log("installing deps now")
    install(clean)
    log("DONE")


if __name__ == "__main__":
    main()
