#!/usr/bin/env python3
"""Swap current and previous Compose deployment inputs without reading their contents."""

from argparse import ArgumentParser
from pathlib import Path
import tempfile


def swap_pair(current: Path, previous: Path) -> None:
    if not current.exists() or not previous.exists():
        raise RuntimeError(f"swap input is missing: {current} or {previous}")
    if current.parent != previous.parent:
        raise RuntimeError("swap inputs must share a parent directory")

    temporary_root = Path(
        tempfile.mkdtemp(prefix=".compose-swap-", dir=current.parent)
    )
    held = temporary_root / "held"
    current.rename(held)
    try:
        previous.rename(current)
    except Exception:
        held.rename(current)
        temporary_root.rmdir()
        raise

    try:
        held.rename(previous)
    except Exception:
        current.rename(previous)
        held.rename(current)
        temporary_root.rmdir()
        raise

    temporary_root.rmdir()


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("--current-dir", required=True, type=Path)
    parser.add_argument("--previous-dir", required=True, type=Path)
    parser.add_argument("--current-env", required=True, type=Path)
    parser.add_argument("--previous-env", required=True, type=Path)
    args = parser.parse_args()

    swap_pair(args.current_dir, args.previous_dir)
    try:
        swap_pair(args.current_env, args.previous_env)
    except Exception:
        try:
            swap_pair(args.current_dir, args.previous_dir)
        except Exception as rollback_error:
            raise RuntimeError(
                "environment swap failed and artifact swap could not be restored"
            ) from rollback_error
        raise


if __name__ == "__main__":
    main()
