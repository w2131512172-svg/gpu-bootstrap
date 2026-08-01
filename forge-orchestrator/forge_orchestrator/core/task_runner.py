from __future__ import annotations

from typing import Any, Callable

from ..clients.comfyui_client import ComfyUIClient
from ..clients.ollama_client import OllamaClient, PromptPlan
from ..workflow.workflow_manager import WorkflowManager


class TaskError(RuntimeError):
    pass


class TaskRunner:
    def __init__(self, config: dict[str, Any]):
        self.ollama = OllamaClient(config["ollama"])
        self.comfyui = ComfyUIClient(config["comfyui"])
        self.workflow = WorkflowManager(config["workflow"])
        self.supported_models = {str(model).strip().lower() for model in config["ollama"].get("supported_models", ["illustrious"])}
        self.max_model_retries = int(config["ollama"].get("max_model_retries", 3))

    def run(self, user_text: str, notify: Callable[[str], None] | None = None) -> dict[str, Any]:
        plan = self._get_valid_plan(user_text, notify or (lambda _message: None))
        if plan.status != "over":
            raise TaskError(f"Ollama returned unexpected status: {plan.status}")
        workflow = self.workflow.build(plan.positive_prompt, plan.negative_prompt)
        prompt_id = self.comfyui.queue_prompt(workflow)
        return {"status": "queued", "prompt_id": prompt_id, "model": plan.model, "positive_prompt": plan.positive_prompt, "negative_prompt": plan.negative_prompt}

    def _get_valid_plan(self, user_text: str, notify: Callable[[str], None]) -> PromptPlan:
        attempts = self.max_model_retries + 1
        for attempt in range(attempts):
            plan = self.ollama.generate_prompt(user_text)
            if plan.model in self.supported_models:
                return plan
            if attempt < attempts - 1:
                notify("Error Model,Reloading.....")
        supported = ", ".join(sorted(self.supported_models))
        raise TaskError(f"Ollama did not return a supported model after {attempts} attempts: {supported}")
