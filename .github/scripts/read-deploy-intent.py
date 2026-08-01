#!/usr/bin/env python3
"""Read and validate the single-tag Ansible deployment intent."""

from pathlib import Path
import re
import sys

ALLOWED_TAGS = {
    "host_files",
    "base",
    "maintenance",
    "storage",
    "docker",
}


def main() -> None:
    intent_path = Path(sys.argv[1])
    meaningful_lines = [
        line.strip()
        for line in intent_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and line.strip() != "---" and not line.lstrip().startswith("#")
    ]

    if len(meaningful_lines) != 1:
        raise SystemExit("deployment intent must contain exactly one tag entry")

    match = re.fullmatch(r"tag:\s*([a-z_]+)", meaningful_lines[0])
    if match is None:
        raise SystemExit("deployment intent must use the form: tag: <approved_tag>")

    tag = match.group(1)
    if tag not in ALLOWED_TAGS:
        allowed = ", ".join(sorted(ALLOWED_TAGS))
        raise SystemExit(f"deployment tag {tag!r} is not allowed; choose one of: {allowed}")

    print(tag)


if __name__ == "__main__":
    main()
