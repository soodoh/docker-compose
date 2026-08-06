#!/usr/bin/env python3
"""Orchestration tests for the qualification shell driver and mutation lease."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

REPOSITORY = Path(__file__).resolve().parents[2]
DRIVER = REPOSITORY / "scripts/qualify-proxmox-lxc"


class QualificationOrchestrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        (self.repo / "scripts").mkdir()
        (self.repo / ".github/scripts").mkdir(parents=True)
        (self.repo / "infrastructure/tofu/proxmox-lxc-qualification").mkdir(parents=True)
        (self.repo / "infrastructure/contract").mkdir(parents=True)
        (self.repo / ".reconcile/lxc-qualification").mkdir(parents=True)
        shutil.copy2(DRIVER, self.repo / "scripts/qualify-proxmox-lxc")
        (self.repo / ".reconcile/lxc-qualification/qualification.tfplan").write_bytes(b"plan")
        (self.repo / ".reconcile/lxc-qualification/manifest.json").write_text("{}\n")
        self.bin = self.repo / "bin"
        self.bin.mkdir()
        self.log = self.repo / "commands.log"
        self._write_fake_commands()
        self.env = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "GITHUB_ACTIONS": "true",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "TF_BACKEND_BUCKET": "test-bucket",
            "AWS_REGION": "test-region",
            "TF_VAR_proxmox_endpoint": "https://proxmox:8006/api2/json",
            "TF_VAR_qualification_vm_id": "9020",
            "TF_VAR_qualification_template_file_id": "local:vztmpl/test.tar.zst",
            "PROXMOX_PLAN_API_TOKEN": "plan-token",
            "PROXMOX_APPLY_API_TOKEN": "apply-token",
            "PROXMOX_CA_PEM": "test-ca",
            "FAKE_LOG": str(self.log),
            "FAKE_COUNTER": str(self.repo / "api-counter"),
            "FAKE_APPLY_RESULT": "success",
            "FAKE_LOCK_COUNT": "0",
        }

    def _executable(self, name: str, content: str) -> None:
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def _write_fake_commands(self) -> None:
        helper = self.repo / ".github/scripts/proxmox-lxc-qualification.py"
        helper.write_text(
            textwrap.dedent(
                """\
                import os
                from pathlib import Path
                import sys

                command = sys.argv[1]
                with Path(os.environ["FAKE_LOG"]).open("a") as log:
                    log.write("helper " + " ".join(sys.argv[1:]) + "\\n")
                if command == "classify-probe-log" and os.environ.get("FAKE_APPLY_RESULT") != "protected":
                    raise SystemExit(1)
                if command == "api-check":
                    counter = Path(os.environ["FAKE_COUNTER"])
                    count = int(counter.read_text()) + 1 if counter.exists() else 1
                    counter.write_text(str(count))
                    if os.environ.get("FAKE_POST_FAILURE") == "1" and count >= 2:
                        raise SystemExit(1)
                    mode = sys.argv[sys.argv.index("--mode") + 1]
                    if os.environ.get("FAKE_RESIDUAL") == "1" and mode == "absent":
                        raise SystemExit(1)
                if command == "inspect-recovery":
                    print(os.environ.get("FAKE_INSPECT_CLASS", "aligned-empty"))
                """
            )
        )
        self._executable(
            "tofu",
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                echo "tofu $*" >>"$FAKE_LOG"
                case " $* " in
                  *" init "*) [[ ${FAKE_INIT_FAILURE:-0} != 1 ]] || exit 1 ;;
                  *" state pull "*) printf '{"resources":[]}\\n' ;;
                  *" show -json "*) printf '{"resource_changes":[]}\\n' ;;
                  *" apply "*)
                    case "$FAKE_APPLY_RESULT" in
                      protected) echo "can't remove CT 9020 - protection mode enabled" >&2; exit 1 ;;
                      generic) echo "generic provider failure" >&2; exit 1 ;;
                    esac
                    ;;
                  *" plan "*)
                    for argument in "$@"; do
                      case "$argument" in -out=*) : >"${argument#-out=}" ;; esac
                    done
                    ;;
                esac
                """
            ),
        )
        self._executable(
            "aws",
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                echo "aws $*" >>"$FAKE_LOG"
                if [[ " $* " == *" s3api list-objects-v2 "* ]]; then
                  echo "$FAKE_LOCK_COUNT"
                fi
                """
            ),
        )
        self._executable(
            "git",
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                case "$*" in
                  "rev-parse HEAD"|"rev-parse origin/main") printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\n' ;;
                  "branch --show-current") echo main ;;
                  "status --porcelain --untracked-files=all") ;;
                  *) exit 1 ;;
                esac
                """
            ),
        )
        self._executable("node", "#!/usr/bin/env bash\necho mutation-leases\n")

    def run_driver(self, *arguments: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = self.env | (extra_env or {})
        return subprocess.run(
            [str(self.repo / "scripts/qualify-proxmox-lxc"), *arguments],
            cwd=self.repo,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def commands(self) -> str:
        return self.log.read_text() if self.log.exists() else ""

    def assert_lease_released(self) -> None:
        commands = self.commands()
        self.assertIn("dynamodb put-item", commands)
        self.assertIn("dynamodb delete-item", commands)

    def assert_lease_retained(self) -> None:
        commands = self.commands()
        self.assertIn("dynamodb put-item", commands)
        self.assertNotIn("dynamodb delete-item", commands)

    def test_expected_protected_delete_rejection_completes_proof_and_releases_lease(self) -> None:
        result = self.run_driver("apply", "probe-protected-delete", extra_env={"FAKE_APPLY_RESULT": "protected"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("classify-probe-log", self.commands())
        self.assertIn("api-check --mode protected", self.commands())
        self.assert_lease_released()

    def test_generic_apply_failure_retains_lease_and_directs_recovery_inspection(self) -> None:
        result = self.run_driver("apply", "probe-protected-delete", extra_env={"FAKE_APPLY_RESULT": "generic"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inspect-recovery", result.stderr)
        self.assert_lease_retained()

    def test_post_proof_failure_retains_lease(self) -> None:
        result = self.run_driver("apply", "create", extra_env={"FAKE_POST_FAILURE": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inspect-recovery", result.stderr)
        self.assert_lease_retained()

    def test_residual_volume_rejection_after_delete_retains_lease(self) -> None:
        result = self.run_driver("apply", "delete", extra_env={"FAKE_RESIDUAL": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("api-check --mode absent", self.commands())
        self.assert_lease_retained()

    def test_complete_delete_and_verify_empty_paths_apply_prove_and_release(self) -> None:
        for operation in ("delete", "verify-empty"):
            with self.subTest(operation=operation):
                self.log.unlink(missing_ok=True)
                Path(self.env["FAKE_COUNTER"]).unlink(missing_ok=True)
                result = self.run_driver("apply", operation)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("tofu -chdir=infrastructure/tofu/proxmox-lxc-qualification apply", self.commands())
                self.assertIn("inspect-plan", self.commands())
                self.assert_lease_released()

    def test_inspect_recovery_reports_sanitized_classes_without_lease_plan_or_apply(self) -> None:
        for classification in (
            "aligned-empty",
            "aligned-protected",
            "aligned-unprotected",
            "live-only-protected",
            "live-only-unprotected",
            "state-only",
            "protection-mismatch",
            "identity-mismatch",
        ):
            with self.subTest(classification=classification):
                self.log.unlink(missing_ok=True)
                result = self.run_driver("inspect-recovery", extra_env={"FAKE_INSPECT_CLASS": classification})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), classification)
                commands = self.commands()
                self.assertNotIn("dynamodb", commands)
                self.assertNotIn(" plan ", commands)
                self.assertNotIn(" apply ", commands)
        self.log.unlink(missing_ok=True)
        result = self.run_driver("inspect-recovery", extra_env={"FAKE_LOCK_COUNT": "1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "lock-present")
        self.assertNotIn("helper inspect-recovery", self.commands())

        self.log.unlink(missing_ok=True)
        result = self.run_driver("inspect-recovery", extra_env={"FAKE_INIT_FAILURE": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "identity-mismatch")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
