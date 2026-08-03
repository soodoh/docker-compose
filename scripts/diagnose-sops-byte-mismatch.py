#!/usr/bin/env python3
"""Report non-secret structural reasons two dotenv files differ."""

from argparse import ArgumentParser
import json
from pathlib import Path
import re

KEY_PATTERN = re.compile(rb"[A-Za-z_][A-Za-z0-9_]*")


def dotenv_structure(data: bytes) -> dict[str, object]:
    lines = data.splitlines(keepends=True)
    assignments: list[tuple[bytes, bytes]] = []
    comment_count = 0
    blank_count = 0
    crlf_count = 0
    trailing_whitespace_count = 0

    for raw_line in lines:
        content = raw_line.removesuffix(b"\n").removesuffix(b"\r")
        if raw_line.endswith(b"\r\n"):
            crlf_count += 1
        if content.rstrip(b" \t") != content:
            trailing_whitespace_count += 1
        stripped = content.strip()
        if not stripped:
            blank_count += 1
            continue
        if stripped.startswith(b"#"):
            comment_count += 1
            continue
        if stripped.startswith(b"export "):
            stripped = stripped.removeprefix(b"export ").lstrip()
        key, separator, value = stripped.partition(b"=")
        key = key.strip()
        if not separator or KEY_PATTERN.fullmatch(key) is None:
            raise SystemExit("dotenv structure contains an invalid assignment")
        assignments.append((key, value))

    return {
        "bytes": len(data),
        "lines": len(lines),
        "final_newline": data.endswith(b"\n"),
        "crlf_lines": crlf_count,
        "comments": comment_count,
        "blank_lines": blank_count,
        "trailing_whitespace_lines": trailing_whitespace_count,
        "assignments": assignments,
    }


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("decrypted", type=Path)
    args = parser.parse_args()

    source_data = args.source.read_bytes()
    decrypted_data = args.decrypted.read_bytes()
    source = dotenv_structure(source_data)
    decrypted = dotenv_structure(decrypted_data)
    source_assignments = source.pop("assignments")
    decrypted_assignments = decrypted.pop("assignments")

    source_by_key = dict(source_assignments)
    decrypted_by_key = dict(decrypted_assignments)
    first_difference = next(
        (
            index
            for index, (source_byte, decrypted_byte) in enumerate(
                zip(source_data, decrypted_data, strict=False)
            )
            if source_byte != decrypted_byte
        ),
        min(len(source_data), len(decrypted_data)),
    )

    print(
        json.dumps(
            {
                "source": source,
                "decrypted": decrypted,
                "first_differing_byte_offset": first_difference,
                "key_set_match": set(source_by_key) == set(decrypted_by_key),
                "key_order_match": [key for key, _value in source_assignments]
                == [key for key, _value in decrypted_assignments],
                "assignment_values_match": source_by_key == decrypted_by_key,
                "assignment_value_mismatch_count": sum(
                    source_by_key.get(key) != decrypted_by_key.get(key)
                    for key in set(source_by_key) | set(decrypted_by_key)
                ),
                "lf_normalized_match": source_data.replace(b"\r\n", b"\n")
                == decrypted_data.replace(b"\r\n", b"\n"),
                "final_newline_normalized_match": source_data.rstrip(b"\r\n")
                == decrypted_data.rstrip(b"\r\n"),
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
