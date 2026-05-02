import re

SKIP_LINE_PATTERNS = [
    # pip option lines
    re.compile(r"^\s*-", re.IGNORECASE),

    # pinned core CUDA stack - managed by bootstrap, never custom_nodes
    re.compile(r"(^|\s)torch([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)torchvision([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)torchaudio([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)xformers([<>=!\[\];\s]|$)", re.IGNORECASE),

    # known platform / index traps
    re.compile(r"mmcv.*piwheels", re.IGNORECASE),
    re.compile(r"triton.*windows", re.IGNORECASE),
    re.compile(r"win_amd64\.whl", re.IGNORECASE),

    # training / dev / optional ecosystem packages; unsafe for ComfyUI runtime
    re.compile(r"^deepspeed([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"^inference-cli([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"^inference-gpu([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"^pytest([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"^mypy([<>=!\[\];\s]|$)", re.IGNORECASE),

    # old hard pins observed to conflict with modern ComfyUI/plugin stack
    re.compile(r"^timm==0\.4\.12$", re.IGNORECASE),
    re.compile(r"^torchscale==0\.2\.0$", re.IGNORECASE),
]

def split_clean_skipped(lines):
    clean = []
    skipped = []

    for line in lines:
        reason = None

        for pattern in SKIP_LINE_PATTERNS:
            if pattern.search(line):
                reason = f"pattern:{pattern.pattern}"
                break

        if reason:
            skipped.append(f"{line}    [skip:{reason}]")
        else:
            clean.append(line)

    return clean, skipped
