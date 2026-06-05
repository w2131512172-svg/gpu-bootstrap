from rules.mapping import modules_to_packages


def repair_from_modules(modules: list[str]) -> list[str]:
    """
    模块列表 → pip 包列表。

    注意：这里不再写入 manual_requirements.txt。
    repair-log 只负责把启动日志里的 ModuleNotFoundError
    转换成本次临时 Pod 可以安装的 pip 包名。

    长期固化仍然由用户手动维护：
    comfyui/deps/manual_requirements.txt
    """
    return modules_to_packages(modules)
