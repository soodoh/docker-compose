#!/usr/bin/env python3
"""Focused tests for the CT retirement lifecycle helper."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name("ct-retirement.py")
SPEC = importlib.util.spec_from_file_location("ct_retirement", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load CT retirement helper")
ct_retirement = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ct_retirement)


class RetirementLifecycleTests(unittest.TestCase):
    def test_permitted_transition_operations(self) -> None:
        expected = {
            ("protected", "protected"): "none",
            ("protected", "unprotected"): "unprotect",
            ("unprotected", "protected"): "none",
            ("unprotected", "unprotected"): "none",
            ("unprotected", "retired"): "delete",
            ("retired", "retired"): "none",
        }
        for stages, operation in expected.items():
            with self.subTest(stages=stages):
                self.assertEqual(ct_retirement.transition_operation(*stages), operation)

    def test_skips_and_transitions_out_of_retired_are_rejected(self) -> None:
        for stages in (
            ("protected", "retired"),
            ("retired", "protected"),
            ("retired", "unprotected"),
        ):
            with self.subTest(stages=stages):
                with self.assertRaises(ct_retirement.RetirementError):
                    ct_retirement.transition_operation(*stages)

    def test_operation_must_match_desired_stage(self) -> None:
        self.assertTrue(ct_retirement.operation_matches_stage("none", "protected"))
        self.assertTrue(ct_retirement.operation_matches_stage("none", "unprotected"))
        self.assertTrue(ct_retirement.operation_matches_stage("none", "retired"))
        self.assertTrue(ct_retirement.operation_matches_stage("unprotect", "unprotected"))
        self.assertTrue(ct_retirement.operation_matches_stage("delete", "retired"))
        self.assertFalse(ct_retirement.operation_matches_stage("unprotect", "protected"))
        self.assertFalse(ct_retirement.operation_matches_stage("delete", "unprotected"))

    def test_exact_confirmation_uses_only_the_environment_value(self) -> None:
        with mock.patch.dict("os.environ", {}, clear=True):
            self.assertFalse(ct_retirement.confirmation_matches())
        fixture = "test-only-confirmation"
        fixture_hash = ct_retirement.hashlib.sha256(fixture.encode()).hexdigest()
        with (
            mock.patch.dict(
                "os.environ", {ct_retirement.CONFIRMATION_ENVIRONMENT: fixture}, clear=True
            ),
            mock.patch.object(ct_retirement, "CONFIRMATION_SHA256", fixture_hash),
        ):
            self.assertTrue(ct_retirement.confirmation_matches())

    def test_confirmation_is_required_for_non_protected_steady_state(self) -> None:
        self.assertFalse(ct_retirement.confirmation_required("none", "protected"))
        for operation, stage in (
            ("unprotect", "unprotected"),
            ("delete", "retired"),
            ("none", "unprotected"),
            ("none", "retired"),
        ):
            with self.subTest(operation=operation, stage=stage):
                self.assertTrue(ct_retirement.confirmation_required(operation, stage))

    def test_non_protected_steady_validation_rejects_missing_or_wrong_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            contract = Path(directory, "contract.yml")
            contract.write_text(
                "proxmox:\n  legacy_container:\n    retirement_stage: retired\n"
            )
            command = [
                sys.executable,
                str(SCRIPT),
                "validate-operation",
                "--contract",
                str(contract),
                "--operation",
                "none",
            ]
            for environment in (
                {},
                {ct_retirement.CONFIRMATION_ENVIRONMENT: "wrong-test-confirmation"},
            ):
                with self.subTest(environment=environment):
                    result = subprocess.run(
                        command,
                        check=False,
                        capture_output=True,
                        text=True,
                        env=environment,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("wrong-test-confirmation", result.stderr)

    def test_contract_stage_is_required_and_enumerated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            contract = Path(directory, "contract.yml")
            contract.write_text("proxmox:\n  legacy_container:\n    retirement_stage: protected\n")
            self.assertEqual(ct_retirement.contract_stage(contract), "protected")
            contract.write_text("proxmox:\n  legacy_container:\n    protected: true\n")
            self.assertEqual(ct_retirement.contract_stage(contract), "protected")
            contract.write_text("proxmox:\n  legacy_container:\n    retirement_stage: skipped\n")
            with self.assertRaises(ct_retirement.RetirementError):
                ct_retirement.contract_stage(contract)

    def test_manifest_binds_exact_operation_and_stage(self) -> None:
        valid = {
            "version": 2,
            "ct_retirement_operation": "unprotect",
            "retirement_stage": "unprotected",
        }
        ct_retirement.verify_manifest_fields(valid, "unprotect", "unprotected")
        for changed in (
            {**valid, "ct_retirement_operation": "delete"},
            {**valid, "retirement_stage": "retired"},
            {**valid, "version": 1},
        ):
            with self.subTest(manifest=changed):
                with self.assertRaises(ct_retirement.RetirementError):
                    ct_retirement.verify_manifest_fields(changed, "unprotect", "unprotected")

    def test_manifest_command_rejects_operation_and_stage_mismatches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            contract = Path(directory, "contract.yml")
            manifest = Path(directory, "manifest.json")
            contract.write_text(
                "proxmox:\n  legacy_container:\n    retirement_stage: unprotected\n"
            )
            manifest.write_text(
                json.dumps(
                    {
                        "version": 2,
                        "ct_retirement_operation": "unprotect",
                        "retirement_stage": "unprotected",
                    }
                )
            )
            command = [
                sys.executable,
                str(SCRIPT),
                "verify-manifest",
                "--manifest",
                str(manifest),
                "--contract",
                str(contract),
                "--operation",
            ]
            self.assertEqual(
                subprocess.run(command + ["unprotect"], check=False).returncode, 0
            )
            self.assertNotEqual(
                subprocess.run(
                    command + ["delete"], check=False, capture_output=True
                ).returncode,
                0,
            )
            contract.write_text(
                "proxmox:\n  legacy_container:\n    retirement_stage: protected\n"
            )
            self.assertNotEqual(
                subprocess.run(
                    command + ["unprotect"], check=False, capture_output=True
                ).returncode,
                0,
            )


if __name__ == "__main__":
    unittest.main()
