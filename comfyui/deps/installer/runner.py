import subprocess
import sys
from pathlib import Path


def run_cmd(cmd: list[str], *, check: bool = True) -> int:
    print("[installer] RUN:", " ".join(cmd))

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


def install_comfyui_requirements(comfyui_root: Path) -> None:
    req = comfyui_root / "requirements.txt"
    if not req.exists():
        print("[installer] comfyui requirements not found:", req)
        return

    print("[installer] install comfyui requirements:", req)
    run_cmd([sys.executable, "-m", "pip", "install", "-r", str(req)])
