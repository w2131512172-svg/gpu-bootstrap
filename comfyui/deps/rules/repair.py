from pathlib import Path
from rules.mapping import modules_to_packages

def append_manual_requirements(manual_path: Path, packages: list[str]) -> list[str]:
    """
    把缺失包追加写入 manual_requirements.txt（去重）
    返回实际新增的包
    """
    existing = set()

    if manual_path.exists():
        for line in manual_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                existing.add(line)

    added = []

    for pkg in packages:
        if pkg in existing:
            continue
        added.append(pkg)
        existing.add(pkg)

    if added:
        with manual_path.open("a", encoding="utf-8") as f:
            for pkg in added:
                f.write(pkg + "\n")

    return added


def repair_from_modules(modules: list[str], manual_path: Path) -> list[str]:
    """
    模块列表 → pip包 → 写入 manual_requirements
    """
    packages = modules_to_packages(modules)
    added = append_manual_requirements(manual_path, packages)
    return added
