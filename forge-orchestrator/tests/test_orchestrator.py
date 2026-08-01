from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from forge_orchestrator.clients.ollama_client import PromptPlan
from forge_orchestrator.core.context_store import ContextStore
from forge_orchestrator.core.task_runner import TaskRunner
from forge_orchestrator.core.text import normalize_unicode
from forge_orchestrator.workflow.workflow_manager import WorkflowManager


class UnicodeTests(unittest.TestCase):
    def test_surrogate_pair_is_repaired(self) -> None:
        broken = "红头发\ud83d\ude00女孩"
        repaired = normalize_unicode(broken)
        self.assertEqual(repaired, "红头发😀女孩")
        repaired.encode("utf-8")


class WorkflowTests(unittest.TestCase):
    def test_prompts_and_seed_are_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "workflow.json"
            path.write_text(
                json.dumps(
                    {
                        "7": {"inputs": {"text": "old negative"}},
                        "12": {"inputs": {"text": "old positive"}},
                        "31": {"inputs": {"seed": 1}},
                    }
                ),
                encoding="utf-8",
            )
            manager = WorkflowManager(
                {
                    "template": str(path),
                    "positive_prompt_node": "12",
                    "negative_prompt_node": "7",
                    "seed_node": "31",
                }
            )
            workflow = manager.build("red hair", "bad quality", seed=12345)
            self.assertEqual(workflow["12"]["inputs"]["text"], "red hair")
            self.assertEqual(workflow["7"]["inputs"]["text"], "bad quality")
            self.assertEqual(workflow["31"]["inputs"]["seed"], 12345)


class ContextStoreTests(unittest.TestCase):
    def test_history_persists_and_clears(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = ContextStore(str(Path(directory) / "context.db"), 20)
            result = {
                "model": "illustrious",
                "positive_prompt": "red hair",
                "negative_prompt": "bad quality",
                "count": 2,
                "items": [
                    {"index": 1, "prompt_id": "p1", "seed": 1},
                    {"index": 2, "prompt_id": "p2", "seed": 2},
                ],
            }
            store.record_success("main", "生成两张红发女孩", result)
            history = ContextStore(str(Path(directory) / "context.db"), 20).get_history(
                "main"
            )
            self.assertEqual([message["role"] for message in history], ["user", "assistant"])
            self.assertIn("生成两张", history[0]["content"])
            store.clear_session("main")
            self.assertEqual(store.get_history("main"), [])


class BatchTests(unittest.TestCase):
    def test_batch_queues_unique_workflows_and_passes_history(self) -> None:
        class FakeOllama:
            received_history = None

            def generate_prompt(self, _text, history):
                self.received_history = history
                return PromptPlan("illustrious", "positive", "negative", 3, "over")

        class FakeWorkflow:
            def build(self, positive, negative, seed):
                return {"positive": positive, "negative": negative, "seed": seed}

        class FakeComfyUI:
            workflows = []

            def queue_prompt(self, workflow):
                self.workflows.append(workflow)
                return f"prompt-{len(self.workflows)}"

        runner = TaskRunner.__new__(TaskRunner)
        runner.ollama = FakeOllama()
        runner.workflow = FakeWorkflow()
        runner.comfyui = FakeComfyUI()
        runner.supported_models = {"illustrious"}
        runner.max_model_retries = 3
        runner.max_batch_size = 20
        history = [{"role": "user", "content": "上一张是红头发"}]
        result = runner.run("改成蓝头发，再来三张", history=history)
        self.assertEqual(result["count"], 3)
        self.assertEqual(len(result["items"]), 3)
        self.assertEqual(runner.ollama.received_history, history)
        seeds = {item["seed"] for item in result["items"]}
        self.assertEqual(len(seeds), 3)


if __name__ == "__main__":
    unittest.main()
