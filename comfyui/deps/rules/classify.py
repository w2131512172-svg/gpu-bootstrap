def is_git_requirement(line: str) -> bool:
    lowered = line.strip().lower()
    return lowered.startswith("git+") or " git+" in lowered

def split_normal_git(lines):
    normal = []
    git = []

    for line in lines:
        if is_git_requirement(line):
            git.append(line)
        else:
            normal.append(line)

    return normal, git
