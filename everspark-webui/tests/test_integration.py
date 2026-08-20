from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


APP_PATH = Path(__file__).resolve().parents[1] / "app.py"
SPEC = importlib.util.spec_from_file_location("everspark_webui_integration", APP_PATH)
assert SPEC and SPEC.loader
app = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = app
SPEC.loader.exec_module(app)

PNG_BYTES = b"\x89PNG\r\n\x1a\nmock-image"


class MockUpstreamHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path in {"/health", "/system_stats"}:
            self._json({"ok": True})
        elif parsed.path == "/history/prompt-1":
            self._json(
                {
                    "prompt-1": {
                        "outputs": {
                            "9": {
                                "images": [
                                    {
                                        "filename": "ComfyUI_00001_.png",
                                        "subfolder": "",
                                        "type": "output",
                                    }
                                ]
                            }
                        }
                    }
                }
            )
        elif parsed.path == "/history":
            self._json(
                {
                    "prompt-1": {
                        "outputs": {
                            "9": {
                                "images": [
                                    {
                                        "filename": "ComfyUI_00001_.png",
                                        "subfolder": "",
                                        "type": "output",
                                    }
                                ]
                            }
                        }
                    }
                }
            )
        elif parsed.path == "/view":
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(PNG_BYTES)))
            self.end_headers()
            self.wfile.write(PNG_BYTES)
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        if self.path != "/tasks":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        self._json(
            {
                "ok": True,
                "result": {
                    "count": 1,
                    "items": [
                        {"index": 1, "prompt_id": "prompt-1", "seed": 123}
                    ],
                    "received_text": payload["text"],
                },
            }
        )

    def _json(self, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


class WebUIIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.log_directory = tempfile.TemporaryDirectory()
        cls.previous_log_dir = os.environ.get("EVERSPARK_LOG_DIR")
        os.environ["EVERSPARK_LOG_DIR"] = cls.log_directory.name
        Path(cls.log_directory.name, "webui.log").write_text(
            "test runtime log\n",
            encoding="utf-8",
        )
        cls.upstream = ThreadingHTTPServer(("127.0.0.1", 0), MockUpstreamHandler)
        upstream_url = f"http://127.0.0.1:{cls.upstream.server_address[1]}"
        cls.webui = app.WebUIServer(
            app.Settings(
                host="127.0.0.1",
                port=0,
                orchestrator_url=upstream_url,
                comfyui_url=upstream_url,
                request_timeout=5,
                comfyui_timeout=5,
            )
        )
        cls.base_url = f"http://127.0.0.1:{cls.webui.server_address[1]}"
        cls.threads = [
            threading.Thread(target=cls.upstream.serve_forever, daemon=True),
            threading.Thread(target=cls.webui.serve_forever, daemon=True),
        ]
        for thread in cls.threads:
            thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.webui.shutdown()
        cls.upstream.shutdown()
        cls.webui.server_close()
        cls.upstream.server_close()
        if cls.previous_log_dir is None:
            os.environ.pop("EVERSPARK_LOG_DIR", None)
        else:
            os.environ["EVERSPARK_LOG_DIR"] = cls.previous_log_dir
        cls.log_directory.cleanup()

    def get_json(self, path: str) -> dict:
        with urlopen(f"{self.base_url}{path}", timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))

    def test_complete_generate_result_and_image_proxy_flow(self) -> None:
        payload = json.dumps(
            {"message": "生成一个红发女孩😊", "session_id": "main"},
            ensure_ascii=False,
        ).encode("utf-8")
        request = Request(
            f"{self.base_url}/api/generate",
            data=payload,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )
        with urlopen(request, timeout=5) as response:
            queued = json.loads(response.read().decode("utf-8"))
        self.assertEqual(queued["result"]["received_text"], "生成一个红发女孩😊")
        self.assertEqual(queued["result"]["items"][0]["prompt_id"], "prompt-1")

        result = self.get_json("/api/results?prompt_id=prompt-1")
        self.assertEqual(result["results"][0]["status"], "completed")
        image_url = result["results"][0]["images"][0]["url"]
        with urlopen(f"{self.base_url}{image_url}", timeout=5) as response:
            self.assertEqual(response.headers.get_content_type(), "image/png")
            self.assertEqual(response.read(), PNG_BYTES)

    def test_recent_history_uses_comfyui_history(self) -> None:
        history = self.get_json("/api/history?limit=24")
        self.assertTrue(history["ok"])
        self.assertEqual(history["images"][0]["filename"], "ComfyUI_00001_.png")

    def test_health_checks_both_services(self) -> None:
        health = self.get_json("/api/health")
        self.assertTrue(health["services"]["orchestrator"]["online"])
        self.assertTrue(health["services"]["comfyui"]["online"])

    def test_runtime_status_includes_logging_summary(self) -> None:
        runtime = self.get_json("/api/runtime/status")
        self.assertTrue(runtime["ok"])
        self.assertTrue(runtime["logging"]["ready"])
        self.assertGreater(runtime["logging"]["configured"], 0)
        self.assertGreaterEqual(runtime["logging"]["present"], 1)

    def test_runtime_logs_follow_manifest(self) -> None:
        runtime = self.get_json("/api/runtime/logs")
        self.assertTrue(runtime["ok"])
        webui = next(item for item in runtime["logs"] if item["id"] == "webui")
        self.assertTrue(webui["exists"])
        self.assertEqual(webui["filename"], "webui.log")
        self.assertNotIn("path", webui)

    def test_runtime_manifest_error_does_not_expose_server_path(self) -> None:
        missing = str(Path(self.log_directory.name) / "private" / "missing.json")
        previous = os.environ.get("EVERSPARK_LOG_MANIFEST")
        os.environ["EVERSPARK_LOG_MANIFEST"] = missing
        try:
            with self.assertRaises(HTTPError) as caught:
                self.get_json("/api/runtime/logs")
            payload = json.loads(caught.exception.read().decode("utf-8"))
            self.assertEqual(payload["error"], "Runtime log manifest is unavailable")
            self.assertNotIn(missing, payload["error"])
        finally:
            if previous is None:
                os.environ.pop("EVERSPARK_LOG_MANIFEST", None)
            else:
                os.environ["EVERSPARK_LOG_MANIFEST"] = previous


if __name__ == "__main__":
    unittest.main()
