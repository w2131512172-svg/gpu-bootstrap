from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any


class WorkflowError(RuntimeError):
    pass


class WorkflowManager:
    def __init__(self, config: dict[str, Any]):
        self.template_path = Path(config["template"])
        self.positive_node = str(config.get("positive_prompt_node", "")).strip()
        self.negative_node = str(config.get("negative_prompt_node", "")).strip()

    def build(self, positive_prompt: str, negative_prompt: str) -> dict[str, Any]:
        workflow = copy.deepcopy(self._load_template())
        self._replace_text(workflow, self.positive_node, positive_prompt, "positive")
        self._replace_text(workflow, self.negative_node, negative_prompt, "negative")
        return workflow

    def _load_template(self) -> dict[str, Any]:
        try:
            raw = self.template_path.read_text(encoding="utf-8")
        except FileNotFoundError as exc:
            raise WorkflowError(f"Workflow template not found: {self.template_path}") from exc
        if not raw.strip():
            raise WorkflowError("ComfyUI API Format workflow is still an empty placeholder. Export it from ComfyUI before running a generation task.")
        try:
            workflow = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise WorkflowError(f"Invalid workflow JSON: {exc}") from exc
        if not isinstance(workflow, dict) or not workflow:
            raise WorkflowError("ComfyUI API Format workflow must be a non-empty JSON object")
        return workflow

    @staticmethod
    def _replace_text(workflow: dict[str, Any], node_id: str, prompt: str, label: str) -> None:
        if not node_id:
            raise WorkflowError(f"The {label}_prompt_node is not configured")
        node = workflow.get(node_id)
        if not isinstance(node, dict):
            raise WorkflowError(f"Workflow node {node_id} ({label}) was not found")
        inputs = node.get("inputs")
        if not isinstance(inputs, dict) or "text" not in inputs:
            raise WorkflowError(f"Workflow node {node_id} ({label}) has no inputs.text")
        inputs["text"] = prompt
