from pathlib import Path
import re

MISSING_RE = re.compile(r"ModuleNotFoundError:\s+No module named ['\"]([^'\"]+)['\"]")

def scan_missing_modules(log_path: Path) -> list[str]:
    """
    纯扫描层：
    只从日志里提取 ModuleNotFoundError 的模块名。
    不判断、不映射、不安装。
    """
    if not log_path.exists():
        return []

    text = log_path.read_text(encoding="utf-8", errors="ignore")
    modules = []

    for match in MISSING_RE.finditer(text):
        modules.append(match.group(1).strip())

    return modules
