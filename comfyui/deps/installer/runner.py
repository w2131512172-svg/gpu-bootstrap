import subprocess
import sys

def run_cmd(cmd: list[str], *, check: bool = True) -> int:
    print("[installer] RUN:", " ".join(cmd))
    proc = subprocess.run(cmd)
    if check and proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return proc.returncode

def upgrade_packaging_tools() -> None:
    run_cmd([sys.executable, "-m", "pip", "install", "-U", "pip", "setuptools", "wheel"])

def install_normal(lines: list[str]) -> None:
    if not lines:
        print("[installer] no normal deps")
        return

    print("[installer] install normal deps:", len(lines))
    run_cmd([sys.executable, "-m", "pip", "install", *lines])

def install_git(lines: list[str]) -> None:
    if not lines:
        print("[installer] no git deps")
        return

    for line in lines:
        print("[installer] install git dep:", line)
        run_cmd([sys.executable, "-m", "pip", "install", "--no-build-isolation", line])

def install_all(normal: list[str], git: list[str], *, upgrade_tools: bool = True) -> None:
    if upgrade_tools:
        upgrade_packaging_tools()

    install_normal(normal)
    install_git(git)

from pathlib import Path

def install_comfyui_requirements(comfyui_root: Path):
    req = comfyui_root / "requirements.txt"
    if not req.exists():
        print("[installer] comfyui requirements not found:", req)
        return

    print("[installer] install comfyui requirements:", req)
    run_cmd([sys.executable, "-m", "pip", "install", "-r", str(req)])
