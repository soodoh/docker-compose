#!/usr/bin/env python3
"""Write only sorted variable names from a dotenv file."""

from argparse import ArgumentParser
import json
from pathlib import Path
import re

KEY_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--layout-output", type=Path)
    args = parser.parse_args()

    source_text = args.source.read_text(encoding="utf-8")
    source_lines = source_text.splitlines()
    blank_lines = [
        line_number
        for line_number, raw_line in enumerate(source_lines, start=1)
        if not raw_line.strip()
    ]
    if any(source_lines[line_number - 1] for line_number in blank_lines):
        raise SystemExit("whitespace-only dotenv lines cannot be represented safely")

    keys: set[str] = set()
    for line_number, raw_line in enumerate(source_lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line.removeprefix("export ").lstrip()
        key, separator, _value = line.partition("=")
        key = key.strip()
        if not separator or KEY_PATTERN.fullmatch(key) is None:
            raise SystemExit(f"invalid dotenv assignment at line {line_number}")
        if key in keys:
            raise SystemExit(f"duplicate dotenv key at line {line_number}")
        keys.add(key)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(f"{key}\n" for key in sorted(keys)), encoding="utf-8")
    if args.layout_output is not None:
        args.layout_output.parent.mkdir(parents=True, exist_ok=True)
        args.layout_output.write_text(
            json.dumps(
                {
                    "version": 1,
                    "source_lines": len(source_lines),
                    "final_newline": source_text.endswith("\n"),
                    "blank_lines": blank_lines,
                },
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
    print(f"dotenv_key_manifest=pass count={len(keys)} blank_lines={len(blank_lines)}")


if __name__ == "__main__":
    main()
