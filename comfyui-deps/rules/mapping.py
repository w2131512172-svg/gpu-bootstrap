MODULE_TO_PACKAGE = {
    # 常见“模块名 != pip包名”
    "cv2": "opencv-python",
    "PIL": "Pillow",
    "yaml": "PyYAML",
    "sklearn": "scikit-learn",
    "bs4": "beautifulsoup4",

    # ComfyUI / Python 生态常见
    "pydantic_settings": "pydantic-settings",
    "dotenv": "python-dotenv",
    "dateutil": "python-dateutil",

    # 模块名和包名一致，也可以显式写进去，方便可读性
    "pandas": "pandas",
    "numpy": "numpy",
}

def module_to_package(module_name: str) -> str:
    """
    把 Python import 模块名转换成 pip 包名。
    未知模块默认原样返回。
    """
    name = module_name.strip()

    # 只取顶层模块，例如 xxx.yyy -> xxx
    top = name.split(".", 1)[0]

    return MODULE_TO_PACKAGE.get(top, top)


def modules_to_packages(module_names: list[str]) -> list[str]:
    seen = set()
    out = []

    for mod in module_names:
        pkg = module_to_package(mod)
        if not pkg:
            continue
        if pkg in seen:
            continue
        seen.add(pkg)
        out.append(pkg)

    return out
