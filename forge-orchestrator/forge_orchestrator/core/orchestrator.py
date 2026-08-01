from __future__ import annotations

import threading
from typing import Any

from .task_runner import TaskRunner


class BusyError(RuntimeError):
    pass


class Orchestrator:
    def __init__(self, config: dict[str, Any]):
        self.runner = TaskRunner(config)
        self._task_lock = threading.Lock()

    def submit(self, user_text: str) -> dict[str, Any]:
        text = user_text.strip()
        if not text:
            raise ValueError("Task text cannot be empty")
        if not self._task_lock.acquire(blocking=False):
            raise BusyError("The first-version Orchestrator is already running one task")
        notices: list[str] = []
        try:
            result = self.runner.run(text, notify=notices.append)
            return {"ok": True, "notices": notices, "result": result}
        finally:
            self._task_lock.release()
