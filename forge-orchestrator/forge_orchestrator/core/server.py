from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from ..config.config import ConfigError, load_config
from .orchestrator import BusyError, Orchestrator


class OrchestratorServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], orchestrator: Orchestrator):
        super().__init__(address, RequestHandler)
        self.orchestrator = orchestrator


class RequestHandler(BaseHTTPRequestHandler):
    server: OrchestratorServer

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send(200, {"ok": True, "status": "standby"})
        else:
            self._send(404, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:
        if self.path != "/tasks":
            self._send(404, {"ok": False, "error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            result = self.server.orchestrator.submit(str(payload.get("text", "")))
            self._send(200, result)
        except BusyError as exc:
            self._send(409, {"ok": False, "error": str(exc)})
        except (ValueError, json.JSONDecodeError) as exc:
            self._send(400, {"ok": False, "error": str(exc)})
        except Exception as exc:
            self._send(500, {"ok": False, "error": str(exc)})

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[Orchestrator] {self.address_string()} - {format % args}")

    def _send(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    try:
        config = load_config()
    except ConfigError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    host = str(config["orchestrator"]["host"])
    port = int(config["orchestrator"]["port"])
    server = OrchestratorServer((host, port), Orchestrator(config))
    print("EverSpark Orchestrator v0.1")
    print(f"Core API: http://{host}:{port}")
    print("Status: standby (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping EverSpark Orchestrator...")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
