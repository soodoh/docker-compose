#!/usr/bin/env python3
"""Focused tests for main-only special infrastructure applies."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

HELPER = Path(__file__).with_name("reconcile-apply-source.py")


def load_helper():
    spec = importlib.util.spec_from_file_location("reconcile_apply_source", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {HELPER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


source = load_helper()
COMMIT = "a" * 40
OTHER_COMMIT = "b" * 40


class FakeGit:
    def __init__(self, *, branch: str = "main", origin_main: str = COMMIT) -> None:
        self.branch = branch
        self.origin_main = origin_main

    def __call__(self, arguments: tuple[str, ...]) -> str:
        values = {
            ("rev-parse", "HEAD"): COMMIT,
            ("symbolic-ref", "--quiet", "--short", "HEAD"): self.branch,
            ("rev-parse", "origin/main"): self.origin_main,
        }
        return values[arguments]


class ApplySourceTests(unittest.TestCase):
    def test_github_requires_exact_main_ref_and_candidate_commit(self) -> None:
        valid = {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": COMMIT}
        source.validate_apply_source(valid, FakeGit())
        for environment in (
            {**valid, "GITHUB_REF": "refs/pull/7/merge"},
            {**valid, "GITHUB_REF": "refs/heads/feature"},
            {**valid, "GITHUB_SHA": OTHER_COMMIT},
            {**valid, "GITHUB_SHA": ""},
        ):
            with self.assertRaises(source.ApplySourceError):
                source.validate_apply_source(environment, FakeGit())

    def test_local_requires_attached_main_at_origin_main(self) -> None:
        source.validate_apply_source({}, FakeGit())
        for git in (
            FakeGit(branch="feature"),
            FakeGit(branch="HEAD"),
            FakeGit(origin_main=OTHER_COMMIT),
        ):
            with self.assertRaises(source.ApplySourceError):
                source.validate_apply_source({}, git)


if __name__ == "__main__":
    unittest.main()
