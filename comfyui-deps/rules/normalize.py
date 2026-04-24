def normalize_lines(rows):
    """
    输入: [(path, raw_line)]
    输出: ["numpy", "torch", ...]
    
    当前只做：
    - 去空行
    - 去注释
    """
    out = []

    for path, raw in rows:
        line = raw.strip()

        if not line:
            continue

        if line.startswith("#"):
            continue

        # 去掉行尾注释
        if " #" in line:
            line = line.split(" #", 1)[0].strip()

        if line:
            out.append(line)

    return out
