from pathlib import Path

REQ_GLOBS = (
    "**/requirements*.txt",
)

def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")

def scan_requirements(custom_nodes: Path) -> list[tuple[Path, str]]:
    """
    纯扫描层：
    只读取 requirements*.txt
    不过滤、不去重、不判断、不安装
    返回: [(文件路径, 原始行), ...]
    """
    results: list[tuple[Path, str]] = []

    for pattern in REQ_GLOBS:
        for path in custom_nodes.glob(pattern):
            if not path.is_file():
                continue

            for line in read_text(path).splitlines():
                results.append((path, line))

    return results
