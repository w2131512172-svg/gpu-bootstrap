from __future__ import annotations

import json
import mimetypes
import os
import sys
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlencode, urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent
STATIC_ROOT = ROOT / "static"
REPO_ROOT = ROOT.parent
sys.path.insert(0, str(REPO_ROOT / "core" / "logging"))

from everspark_logging import EverSparkLogger, get_logger  # noqa: E402

LOG_DIR = Path(os.environ.get("EVERSPARK_LOG_DIR", "/root/everspark_logs"))
LOG_FILE = Path(os.environ.get("EVERSPARK_WEBUI_LOG", str(LOG_DIR / "webui.log")))


@dataclass(frozen=True)
class Settings:
    host: str = "127.0.0.1"
    port: int = 8780
    orchestrator_url: str = "http://127.0.0.1:8765"
    comfyui_url: str = "http://127.0.0.1:8188"
    request_timeout: int = 600
    comfyui_timeout: int = 60


def load_settings() -> Settings:
    config_path = Path(
        os.environ.get("EVERSPARK_WEBUI_CONFIG", ROOT / "config.json")
    ).expanduser()
    values: dict[str, Any] = {}
    if config_path.is_file():
        values = json.loads(config_path.read_text(encoding="utf-8"))

    def value(env: str, key: str, default: Any) -> Any:
        return os.environ.get(env, values.get(key, default))

    return Settings(
        host=str(value("EVERSPARK_WEBUI_HOST", "host", "127.0.0.1")),
        port=int(value("EVERSPARK_WEBUI_PORT", "port", 8780)),
        orchestrator_url=str(
            value(
                "EVERSPARK_ORCHESTRATOR_URL",
                "orchestrator_url",
                "http://127.0.0.1:8765",
            )
        ).rstrip("/"),
        comfyui_url=str(
            value(
                "EVERSPARK_COMFYUI_URL",
                "comfyui_url",
                "http://127.0.0.1:8188",
            )
        ).rstrip("/"),
        request_timeout=int(
            value("EVERSPARK_WEBUI_REQUEST_TIMEOUT", "request_timeout", 600)
        ),
        comfyui_timeout=int(
            value("EVERSPARK_COMFYUI_TIMEOUT", "comfyui_timeout", 60)
        ),
    )


def request_json(
    url: str,
    timeout: int,
    payload: dict[str, Any] | None = None,
) -> tuple[int, dict[str, Any]]:
    data = None
    method = "GET"
    headers: dict[str, str] = {}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        method = "POST"
        headers["Content-Type"] = "application/json; charset=utf-8"
    request = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
            return response.status, body
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            return exc.code, json.loads(raw)
        except json.JSONDecodeError:
            return exc.code, {"ok": False, "error": raw or f"HTTP {exc.code}"}


def image_proxy_url(image: dict[str, Any]) -> str:
    query = urlencode(
        {
            "filename": str(image.get("filename", "")),
            "subfolder": str(image.get("subfolder", "")),
            "type": str(image.get("type", "output")),
        }
    )
    return f"/api/comfy/view?{query}"


def extract_images(history_item: dict[str, Any]) -> list[dict[str, str]]:
    images: list[dict[str, str]] = []
    outputs = history_item.get("outputs", {})
    if not isinstance(outputs, dict):
        return images
    for node_id, output in outputs.items():
        if not isinstance(output, dict):
            continue
        for image in output.get("images", []):
            if not isinstance(image, dict) or not image.get("filename"):
                continue
            normalized = {
                "node_id": str(node_id),
                "filename": str(image["filename"]),
                "subfolder": str(image.get("subfolder", "")),
                "type": str(image.get("type", "output")),
            }
            normalized["url"] = image_proxy_url(normalized)
            images.append(normalized)
    return images


def history_status(history_item: dict[str, Any], images: list[dict[str, str]]) -> str:
    if images:
        return "completed"
    status = history_item.get("status", {})
    if isinstance(status, dict):
        status_text = str(status.get("status_str", "")).lower()
        if status_text in {"error", "failed"}:
            return "failed"
        if status.get("completed") is True:
            return "completed"
    return "running"


class WebUIServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        settings: Settings,
        logger: EverSparkLogger | None = None,
    ):
        super().__init__((settings.host, settings.port), RequestHandler)
        self.settings = settings
        self.logger = logger


class RequestHandler(BaseHTTPRequestHandler):
    server: WebUIServer

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/health":
            self._health()
        elif parsed.path == "/api/results":
            self._results(parse_qs(parsed.query))
        elif parsed.path == "/api/history":
            self._history(parse_qs(parsed.query))
        elif parsed.path == "/api/comfy/view":
            self._proxy_image(parse_qs(parsed.query))
        elif parsed.path == "/":
            self._static("index.html")
        elif parsed.path.startswith("/static/"):
            self._static(parsed.path.removeprefix("/static/"))
        else:
            self._json(404, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/generate":
            self._json(404, {"ok": False, "error": "Not found"})
            return
        try:
            payload = self._read_json()
            message = str(payload.get("message", "")).strip()
            session_id = str(payload.get("session_id", "main")).strip()
            if not message:
                self._json(400, {"ok": False, "error": "请输入创作内容"})
                return
            status, response = request_json(
                f"{self.server.settings.orchestrator_url}/tasks",
                self.server.settings.request_timeout,
                {"text": message, "session_id": session_id},
            )
            self._json(status, response)
        except json.JSONDecodeError:
            self._log("warning", "request.invalid_json", "WebUI request contained invalid JSON")
            self._json(400, {"ok": False, "error": "请求不是有效的 JSON"})
        except (URLError, TimeoutError) as exc:
            self._log(
                "warning",
                "orchestrator.unavailable",
                "WebUI could not reach Orchestrator",
                error_type=type(exc).__name__,
            )
            self._json(
                502,
                {
                    "ok": False,
                    "error": f"无法连接 Orchestrator：{getattr(exc, 'reason', exc)}",
                },
            )
        except Exception as exc:
            self._log(
                "error",
                "request.failed",
                "WebUI generation request failed",
                error_type=type(exc).__name__,
                error=str(exc),
            )
            self._json(500, {"ok": False, "error": str(exc)})

    def _health(self) -> None:
        services: dict[str, dict[str, Any]] = {}
        checks = {
            "orchestrator": (
                f"{self.server.settings.orchestrator_url}/health",
                self.server.settings.comfyui_timeout,
            ),
            "comfyui": (
                f"{self.server.settings.comfyui_url}/system_stats",
                self.server.settings.comfyui_timeout,
            ),
        }
        for name, (url, timeout) in checks.items():
            try:
                status, _ = request_json(url, timeout)
                services[name] = {"online": 200 <= status < 300}
            except Exception as exc:
                services[name] = {"online": False, "error": str(exc)}
        self._json(
            200,
            {"ok": True, "services": services},
        )

    def _results(self, query: dict[str, list[str]]) -> None:
        prompt_ids = [item for item in query.get("prompt_id", []) if item]
        if not prompt_ids:
            self._json(400, {"ok": False, "error": "prompt_id is required"})
            return
        results = []
        try:
            for prompt_id in prompt_ids:
                safe_id = quote(prompt_id, safe="")
                status_code, history = request_json(
                    f"{self.server.settings.comfyui_url}/history/{safe_id}",
                    self.server.settings.comfyui_timeout,
                )
                if not 200 <= status_code < 300:
                    raise RuntimeError(f"ComfyUI history HTTP {status_code}")
                item = history.get(prompt_id)
                if not isinstance(item, dict):
                    results.append(
                        {"prompt_id": prompt_id, "status": "waiting", "images": []}
                    )
                    continue
                images = extract_images(item)
                results.append(
                    {
                        "prompt_id": prompt_id,
                        "status": history_status(item, images),
                        "images": images,
                    }
                )
            self._json(200, {"ok": True, "results": results})
        except (URLError, TimeoutError) as exc:
            self._json(
                502,
                {
                    "ok": False,
                    "error": f"无法连接 ComfyUI：{getattr(exc, 'reason', exc)}",
                },
            )
        except Exception as exc:
            self._json(502, {"ok": False, "error": str(exc)})

    def _history(self, query: dict[str, list[str]]) -> None:
        try:
            limit = max(1, min(100, int(query.get("limit", ["24"])[0])))
        except ValueError:
            self._json(400, {"ok": False, "error": "limit must be an integer"})
            return
        try:
            status, history = request_json(
                f"{self.server.settings.comfyui_url}/history?{urlencode({'max_items': limit})}",
                self.server.settings.comfyui_timeout,
            )
            if not 200 <= status < 300:
                raise RuntimeError(f"ComfyUI history HTTP {status}")
            entries = []
            if isinstance(history, dict):
                for prompt_id, item in reversed(list(history.items())):
                    if not isinstance(item, dict):
                        continue
                    for image in extract_images(item):
                        image["prompt_id"] = str(prompt_id)
                        entries.append(image)
            self._json(200, {"ok": True, "images": entries[:limit]})
        except (URLError, TimeoutError) as exc:
            self._json(
                502,
                {
                    "ok": False,
                    "error": f"无法连接 ComfyUI：{getattr(exc, 'reason', exc)}",
                },
            )
        except Exception as exc:
            self._json(502, {"ok": False, "error": str(exc)})

    def _proxy_image(self, query: dict[str, list[str]]) -> None:
        filename = query.get("filename", [""])[0]
        subfolder = query.get("subfolder", [""])[0]
        folder_type = query.get("type", ["output"])[0]
        if not filename or filename.startswith("/") or ".." in filename:
            self._json(400, {"ok": False, "error": "Invalid filename"})
            return
        if subfolder.startswith("/") or ".." in subfolder:
            self._json(400, {"ok": False, "error": "Invalid subfolder"})
            return
        if folder_type not in {"output", "temp", "input"}:
            self._json(400, {"ok": False, "error": "Invalid image type"})
            return
        upstream_query = urlencode(
            {"filename": filename, "subfolder": subfolder, "type": folder_type}
        )
        request = Request(
            f"{self.server.settings.comfyui_url}/view?{upstream_query}",
            method="GET",
        )
        try:
            with urlopen(request, timeout=self.server.settings.comfyui_timeout) as response:
                body = response.read()
                self.send_response(response.status)
                self.send_header(
                    "Content-Type",
                    response.headers.get("Content-Type", "application/octet-stream"),
                )
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "private, max-age=3600")
                self.end_headers()
                self.wfile.write(body)
        except HTTPError as exc:
            self._json(exc.code, {"ok": False, "error": "图片不存在"})
        except (URLError, TimeoutError) as exc:
            self._json(
                502,
                {
                    "ok": False,
                    "error": f"无法读取 ComfyUI 图片：{getattr(exc, 'reason', exc)}",
                },
            )

    def _static(self, relative_path: str) -> None:
        target = (STATIC_ROOT / relative_path).resolve()
        try:
            target.relative_to(STATIC_ROOT.resolve())
        except ValueError:
            self._json(403, {"ok": False, "error": "Forbidden"})
            return
        if not target.is_file():
            self._json(404, {"ok": False, "error": "Not found"})
            return
        body = target.read_bytes()
        mime_type, _ = mimetypes.guess_type(target.name)
        self.send_response(200)
        self.send_header("Content-Type", f"{mime_type or 'application/octet-stream'}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(payload, dict):
            raise json.JSONDecodeError("Object required", "", 0)
        return payload

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        self._log(
            "info",
            "http.access",
            "HTTP request completed",
            client=self.address_string(),
            request=format % args,
        )

    def _log(self, level: str, event: str, message: str, **fields: Any) -> None:
        if self.server.logger is not None:
            getattr(self.server.logger, level)(event, message, **fields)


def main() -> int:
    logger = get_logger("webui", LOG_FILE)
    server: WebUIServer | None = None
    try:
        settings = load_settings()
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        logger.error(
            "config.invalid",
            "EverSpark WebUI configuration is invalid",
            error_type=type(exc).__name__,
            error=str(exc),
        )
        logger.close()
        return 1
    try:
        server = WebUIServer(settings, logger)
        logger.ok(
            "server.ready",
            "EverSpark WebUI is ready",
            host=settings.host,
            port=settings.port,
        )
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("server.stop.requested", "WebUI shutdown requested")
    except Exception as exc:
        logger.error(
            "server.failed",
            "EverSpark WebUI server failed",
            error_type=type(exc).__name__,
            error=str(exc),
        )
        return 1
    finally:
        if server is not None:
            server.server_close()
            logger.ok("server.stopped", "EverSpark WebUI stopped")
        logger.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
