import re

SKIP_LINE_PATTERNS = [
    re.compile(r"(^|\s)torch([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)torchvision([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)torchaudio([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"(^|\s)xformers([<>=!\[\];\s]|$)", re.IGNORECASE),
    re.compile(r"mmcv.*piwheels", re.IGNORECASE),
    re.compile(r"triton.*windows", re.IGNORECASE),
    re.compile(r"win_amd64\.whl", re.IGNORECASE),
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
