from __future__ import annotations

import json
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from ..config.config import ConfigError, load_config


def submit(base_url: str, text: str, timeout: int) -> dict[str, Any]:
    request = Request(f"{base_url}/tasks", data=json.dumps({"text": text}, ensure_ascii=False).encode("utf-8"), headers={"Content-Type": "application/json; charset=utf-8"}, method="POST")
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        try:
            return json.loads(exc.read().decode("utf-8"))
        except json.JSONDecodeError:
            return {"ok": False, "error": f"Orchestrator HTTP {exc.code}"}
    except URLError as exc:
        return {"ok": False, "error": f"无法连接 Orchestrator Core：{exc.reason}。请先运行 start_core.sh。"}


def main() -> int:
    try:
        config = load_config()
    except ConfigError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    settings = config["orchestrator"]
    base_url = f"http://{settings['host']}:{settings['port']}"
    timeout = int(settings.get("request_timeout", 600))
    print("EverSpark Orchestrator Console")
    print("输入中文绘图需求并回车；输入 /exit 退出。")
    while True:
        try:
            text = input("\nEverSpark > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已退出。")
            return 0
        if not text:
            continue
        if text.lower() in {"/exit", "/quit", "exit", "quit"}:
            print("已退出。")
            return 0
        response = submit(base_url, text, timeout)
        for notice in response.get("notices", []):
            print(notice)
        if not response.get("ok"):
            print(f"[ERROR] {response.get('error', '未知错误')}")
            continue
        result = response["result"]
        print(f"任务已提交给 ComfyUI：{result['prompt_id']}")
        print(f"绘图模型：{result['model']}")


if __name__ == "__main__":
    raise SystemExit(main())
