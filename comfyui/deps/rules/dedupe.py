def dedupe_keep_order(lines):
    """
    保持顺序去重：
    第一次出现的保留，后面重复的丢弃。
    """
    seen = set()
    out = []

    for line in lines:
        key = line.strip()
        if not key:
            continue

        if key in seen:
            continue

        seen.add(key)
        out.append(key)

    return out
