#!/usr/bin/env python3
"""Static safety tests for the production-mutating LXC qualification workflow."""

from __future__ import annotations

from pathlib import Path
import re
import unittest

WORKFLOW = Path(__file__).resolve().parents[1] / "workflows/proxmox-lxc-qualification.yml"


class QualificationWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text()

    def test_workflow_is_manual_main_only_and_enumerates_operations(self) -> None:
        trigger = self.workflow.split("permissions:", 1)[0]
        self.assertIn("workflow_dispatch:", trigger)
        self.assertNotIn("pull_request:", trigger)
        self.assertNotIn("push:", trigger)
        for operation in (
            "create",
            "probe-protected-delete",
            "verify-protected",
            "unprotect",
            "delete",
            "verify-empty",
            "reprotect",
            "inspect-recovery",
        ):
            self.assertIn(f"          - {operation}\n", trigger)
        self.assertGreaterEqual(self.workflow.count("github.ref == 'refs/heads/main'"), 3)

    def test_mutation_uses_distinct_protected_environments_and_exact_driver(self) -> None:
        self.assertIn("environment: infrastructure-plan", self.workflow)
        self.assertIn("environment: infrastructure-apply", self.workflow)
        self.assertIn("PROXMOX_PLAN_API_TOKEN: ${{ secrets.PROXMOX_PLAN_API_TOKEN }}", self.workflow)
        self.assertIn("PROXMOX_APPLY_API_TOKEN: ${{ secrets.PROXMOX_APPLY_API_TOKEN }}", self.workflow)
        self.assertIn("./scripts/qualify-proxmox-lxc plan '${{ inputs.operation }}'", self.workflow)
        self.assertIn("./scripts/qualify-proxmox-lxc apply '${{ inputs.operation }}'", self.workflow)
        self.assertIn("./scripts/qualify-proxmox-lxc inspect-recovery", self.workflow)
        self.assertIn("group: infrastructure-production", self.workflow)
        self.assertIn("cancel-in-progress: false", self.workflow)

    def test_external_actions_are_commit_pinned(self) -> None:
        external_uses = re.findall(r"^\s*uses: ([^\s]+)", self.workflow, re.MULTILINE)
        self.assertTrue(external_uses)
        for action in external_uses:
            if action.startswith("./"):
                continue
            with self.subTest(action=action):
                self.assertRegex(action, r"^[^@]+@[0-9a-f]{40}$")


if __name__ == "__main__":
    unittest.main()
