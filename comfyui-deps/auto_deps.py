#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
from pathlib import Path


BASE = Path(__file__).resolve().parent
CUSTOM_NODES = BASE / "custom_nodes"

# Output files: write directly into current directory
OUT = BASE / "custom_nodes.clean.txt"
SKIP = BASE / "custom_nodes.skipped.txt"

SCAN_PATTERNS = [
    "requirements.txt",
    "requirements*.txt",
    "pyproject.toml",
    "setup.py",
    "setup.cfg",
]

PINNED_PREFIX = ("torch", "torchvision", "torchaudio", "xformers")
SKIP_SUBSTR = ("piwheels.org/simple/mmcv", "triton-windows")
WIN_WHL_RE = re.compile(r"^https?://.*win_amd64\.whl", re.I)


def run(cmd: list[str]) -> None:
    print("[auto_deps] $", " ".join(cmd))
    subprocess.check_call(cmd)


def iter_dep_files() -> list[Path]:
    files: list[Path] = []
    for pattern in SCAN_PATTERNS:
        files.extend(CUSTOM_NODES.rglob(pattern))
    return sorted(set(files))


def parse_requirements_txt(path: Path) -> list[str]:
    result: list[str] = []

    for raw in path.read_text(errors="ignore").splitlines():
        line = raw.strip()

        if not line or line.startswith("#"):
            continue

        # Skip local relative paths like ./xxx or /xxx
        if line.startswith((".", "/")):
            continue

        result.append(line)

    return result


def normalize(line: str) -> str:
    return " ".join(line.split()).strip().lower()


def is_pinned(line: str) -> bool:
    normalized = normalize(line)
    return any(
        normalized == prefix
        or normalized.startswith(prefix + "==")
        or normalized.startswith(prefix + ">=")
        or normalized.startswith(prefix + "<")
        or normalized.startswith(prefix + "~=")
        for prefix in PINNED_PREFIX
    )


def is_skip_link(line: str) -> bool:
    if any(text in line for text in SKIP_SUBSTR):
        return True
    if WIN_WHL_RE.search(line):
        return True
    return False


def scan_and_write() -> tuple[list[str], list[str]]:
    dep_files = iter_dep_files()

    merged: list[str] = []
    for file_path in dep_files:
        if file_path.name.startswith("requirements") and file_path.suffix == ".txt":
            merged.extend(parse_requirements_txt(file_path))

    seen: set[str] = set()
    deduped: list[str] = []
    for item in merged:
        key = normalize(item)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)

    clean: list[str] = []
    skipped: list[str] = []

    for item in deduped:
        if is_pinned(item):
            skipped.append(f"{item}  # pinned (torch/vision/audio/xformers)")
            continue

        if is_skip_link(item):
            skipped.append(f"{item}  # skipped (platform-specific link)")
            continue

        clean.append(item)

    OUT.write_text("\n".join(clean) + ("\n" if clean else ""), encoding="utf-8")
    SKIP.write_text("\n".join(skipped) + ("\n" if skipped else ""), encoding="utf-8")

    return clean, skipped


def install(clean: list[str]) -> None:
    git_deps = [item for item in clean if item.lower().startswith("git+")]
    normal_deps = [item for item in clean if not item.lower().startswith("git+")]

    # Upgrade tooling first
    run(["python", "-m", "pip", "install", "-U", "pip", "setuptools", "wheel"])

    # Install ComfyUI root requirements first
    root_req = BASE.parent / "requirements.txt"
    if root_req.exists():
        print("[auto_deps] installing ComfyUI root requirements:", root_req)
        run(["python", "-m", "pip", "install", "-r", str(root_req)])
    else:
        print("[auto_deps] WARN: ComfyUI root requirements.txt not found:", root_req)

    if normal_deps:
        run(["python", "-m", "pip", "install", "--upgrade", *normal_deps])

    if git_deps:
        for git_dep in git_deps:
            run(["python", "-m", "pip", "install", "--no-build-isolation", git_dep])


def main() -> None:
    print("[auto_deps] root:", BASE)

    if not CUSTOM_NODES.exists():
        raise SystemExit("custom_nodes not found")

    clean, skipped = scan_and_write()

    print("[auto_deps] clean lines:", len(clean))
    print("[auto_deps] skipped lines:", len(skipped))
    print("[auto_deps] wrote:", OUT)
    print("[auto_deps] wrote:", SKIP)

    print("[auto_deps] installing deps now.")
    install(clean)
    print("[auto_deps] DONE")


if __name__ == "__main__":
    main()
