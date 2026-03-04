#!/usr/bin/env python3
from __future__ import annotations
import re
import subprocess
from pathlib import Path

BASE = Path(__file__).resolve().parent
CUSTOM_NODES = BASE / "custom_nodes"
DEPS_DIR = BASE / "deps"
OUT = DEPS_DIR / "custom_nodes.clean.txt"
SKIP = DEPS_DIR / "custom_nodes.skipped.txt"

SCAN_PATTERNS = ["requirements.txt","requirements*.txt","pyproject.toml","setup.py","setup.cfg"]
PINNED_PREFIX = ("torch", "torchvision", "torchaudio", "xformers")
SKIP_SUBSTR = ("piwheels.org/simple/mmcv", "triton-windows")
WIN_WHL_RE = re.compile(r"^https?://.*win_amd64\.whl", re.I)

def run(cmd: list[str]) -> None:
    print("[auto_deps] $", " ".join(cmd))
    subprocess.check_call(cmd)

def iter_dep_files() -> list[Path]:
    files = []
    for pat in SCAN_PATTERNS:
        files += list(CUSTOM_NODES.rglob(pat))
    return sorted(set(files))

def parse_requirements_txt(p: Path) -> list[str]:
    out=[]
    for raw in p.read_text(errors="ignore").splitlines():
        s=raw.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith((".", "/")):
            continue
        out.append(s)
    return out

def normalize(s: str) -> str:
    return " ".join(s.split()).strip().lower()

def is_pinned(line: str) -> bool:
    n = normalize(line)
    return any(
        n == p or n.startswith(p + "==") or n.startswith(p + ">=") or n.startswith(p + "<") or n.startswith(p + "~=")
        for p in PINNED_PREFIX
    )

def is_skip_link(line: str) -> bool:
    if any(x in line for x in SKIP_SUBSTR):
        return True
    if WIN_WHL_RE.search(line):
        return True
    return False

def scan_and_write() -> tuple[list[str], list[str]]:
    dep_files = iter_dep_files()
    merged=[]
    for f in dep_files:
        if f.name.startswith("requirements") and f.suffix == ".txt":
            merged += parse_requirements_txt(f)

    seen=set()
    merged2=[]
    for x in merged:
        k=normalize(x)
        if k in seen:
            continue
        seen.add(k)
        merged2.append(x)

    clean=[]
    skipped=[]
    for x in merged2:
        if is_pinned(x):
            skipped.append(f"{x}  # pinned (torch/vision/audio/xformers)")
            continue
        if is_skip_link(x):
            skipped.append(f"{x}  # skipped (platform-specific link)")
            continue
        clean.append(x)

    DEPS_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(clean) + "\n")
    SKIP.write_text("\n".join(skipped) + "\n")
    return clean, skipped

def install(clean: list[str]) -> None:
    # Split git deps and normal deps
    git_deps = [x for x in clean if x.lower().startswith("git+")]
    normal = [x for x in clean if not x.lower().startswith("git+")]

    # Upgrade tooling first
    run(["python", "-m", "pip", "install", "-U", "pip", "setuptools", "wheel"])

    if normal:
        # Install normal deps in one go
        run(["python", "-m", "pip", "install", "--upgrade"] + normal)

    if git_deps:
        # Install git deps one-by-one with --no-build-isolation (avoid hangs)
        for g in git_deps:
            run(["python", "-m", "pip", "install", "--no-build-isolation", g])

def main():
    print("[auto_deps] root:", BASE)
    if not CUSTOM_NODES.exists():
        raise SystemExit("custom_nodes not found")

    clean, skipped = scan_and_write()
    print("[auto_deps] clean lines:", len(clean))
    print("[auto_deps] skipped lines:", len(skipped))
    print("[auto_deps] wrote:", OUT)
    print("[auto_deps] wrote:", SKIP)

    print("[auto_deps] installing deps now...")
    install(clean)
    print("[auto_deps] DONE")

if __name__=="__main__":
    main()
