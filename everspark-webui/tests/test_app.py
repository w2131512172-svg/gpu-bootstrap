from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


APP_PATH = Path(__file__).resolve().parents[1] / "app.py"
SPEC = importlib.util.spec_from_file_location("everspark_webui_app", APP_PATH)
assert SPEC and SPEC.loader
app = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = app
SPEC.loader.exec_module(app)


class ResultParsingTests(unittest.TestCase):
    def test_extracts_all_comfyui_images(self) -> None:
        item = {
            "outputs": {
                "9": {
                    "images": [
                        {
                            "filename": "ComfyUI_00001_.png",
                            "subfolder": "batch",
                            "type": "output",
                        }
                    ]
                },
                "10": {"text": ["ignored"]},
            }
        }
        images = app.extract_images(item)
        self.assertEqual(len(images), 1)
        self.assertEqual(images[0]["node_id"], "9")
        self.assertEqual(images[0]["filename"], "ComfyUI_00001_.png")
        self.assertIn("filename=ComfyUI_00001_.png", images[0]["url"])
        self.assertIn("subfolder=batch", images[0]["url"])

    def test_completed_status_when_image_exists(self) -> None:
        self.assertEqual(app.history_status({}, [{"filename": "x.png"}]), "completed")

    def test_failed_status_from_comfyui_history(self) -> None:
        item = {"status": {"status_str": "error", "completed": False}}
        self.assertEqual(app.history_status(item, []), "failed")

    def test_running_status_before_outputs_exist(self) -> None:
        self.assertEqual(app.history_status({}, []), "running")


if __name__ == "__main__":
    unittest.main()
