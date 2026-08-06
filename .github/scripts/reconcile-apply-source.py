#!/usr/bin/env python3
"""Require special infrastructure applies to run from the exact main commit."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence


class ApplySourceError(ValueError):
    """Raised when the current checkout cannot authorize a special apply."""


Git = Callable[[Sequence[str]], str]


def run_git(arguments: Sequence[str]) -> str:
    result = subprocess.run(
        ["git", *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def validate_apply_source(environment: Mapping[str, str], git: Git = run_git) -> None:
    current_commit = git(("rev-parse", "HEAD"))
    if re.fullmatch(r"[0-9a-f]{40}", current_commit) is None:
        raise ApplySourceError("current commit identity is invalid")

    if environment.get("GITHUB_ACTIONS") == "true":
        if environment.get("GITHUB_REF") != "refs/heads/main":
            raise ApplySourceError("GitHub lifecycle apply requires exact refs/heads/main")
        github_sha = environment.get("GITHUB_SHA", "")
        if re.fullmatch(r"[0-9a-f]{40}", github_sha) is None or current_commit != github_sha:
            raise ApplySourceError("GitHub lifecycle apply checkout differs from GITHUB_SHA")
        return

    branch = git(("symbolic-ref", "--quiet", "--short", "HEAD"))
    if branch != "main":
        raise ApplySourceError("local lifecycle apply requires the checked-out main branch")
    origin_main = git(("rev-parse", "origin/main"))
    if re.fullmatch(r"[0-9a-f]{40}", origin_main) is None or current_commit != origin_main:
        raise ApplySourceError("local lifecycle apply commit differs from origin/main")


def main() -> int:
    try:
        validate_apply_source(os.environ)
        return 0
    except (ApplySourceError, subprocess.CalledProcessError) as error:
        print(f"Lifecycle apply source validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
