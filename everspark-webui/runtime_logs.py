from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / "core" / "logging"))

from log_manifest import collect_log_status


def runtime_log_status(
    manifest_path: str | Path | None = None,
    log_dir: str | Path | None = None,
    environ: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    return collect_log_status(
        manifest_path=manifest_path,
        log_dir=log_dir,
        environ=environ,
    )
