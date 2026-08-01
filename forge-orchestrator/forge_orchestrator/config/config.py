from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = Path(__file__).with_name("default_config.json")


class ConfigError(RuntimeError):
    pass


def load_config(path: str | Path | None = None) -> dict[str, Any]:
    selected = Path(path or os.environ.get("EVERSPARK_ORCHESTRATOR_CONFIG", "") or DEFAULT_CONFIG_PATH).expanduser().resolve()
    try:
        config = json.loads(selected.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"Config file not found: {selected}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"Invalid JSON config: {selected}: {exc}") from exc
    for section in ("orchestrator", "ollama", "comfyui", "workflow"):
        if not isinstance(config.get(section), dict):
            raise ConfigError(f"Missing config section: {section}")
    workflow_path = Path(config["workflow"]["template"])
    if not workflow_path.is_absolute():
        workflow_path = PACKAGE_ROOT / workflow_path
    config["workflow"]["template"] = str(workflow_path.resolve())
    config["_config_path"] = str(selected)
    return config
