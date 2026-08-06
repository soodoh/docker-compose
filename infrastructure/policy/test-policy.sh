#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
policy="$root/inspect-plan.py"
fixtures="$root/fixtures"

expect_rejection() {
  local fixture=$1 mode=$2
  if python3 "$policy" "$fixtures/$fixture.json" --mode "$mode" >/dev/null 2>&1; then
    echo "expected policy rejection for $fixture in $mode mode" >&2
    exit 1
  fi
}

python3 "$policy" "$fixtures/noop.json"
python3 "$policy" "$fixtures/adopt-import.json" --mode adopt
python3 "$policy" "$fixtures/adopt-noop.json" --mode adopt-or-noop
python3 "$policy" "$fixtures/recovery-create.json" --mode recovery
python3 "$policy" "$fixtures/network-migration.json" --mode network-migration
python3 "$policy" "$fixtures/ct-unprotect.json" --mode ct-unprotect
python3 "$policy" "$fixtures/ct-delete.json" --mode ct-delete
python3 "$policy" "$fixtures/protection-enable.json"
python3 "$policy" "$fixtures/retired-branch-policy-delete.json"
python3 "$policy" "$fixtures/qualification-create.json" --mode qualification
python3 "$policy" "$fixtures/qualification-delete.json" --mode qualification
python3 "$root/../../.github/scripts/test-tailscale-gateway-policy.py"
python3 "$root/../../.github/scripts/test-reconcile-apply-source.py"

for fixture in delete replace protection-disable ct-create ct-recreate; do
  expect_rejection "$fixture" normal
done
for fixture in recovery-wrong-vm recovery-update; do
  expect_rejection "$fixture" recovery
done
for fixture in network-migration-extra-change mapping-device-change; do
  expect_rejection "$fixture" network-migration
done
expect_rejection qualification-wrong-resource qualification

# CT retirement modes are intentionally non-interchangeable and non-repeatable.
expect_rejection ct-delete ct-unprotect
expect_rejection ct-unprotect ct-delete
expect_rejection noop ct-unprotect
expect_rejection noop ct-delete
expect_rejection ct-wrong-id ct-unprotect
expect_rejection ct-wrong-id ct-delete
expect_rejection ct-delete-protected ct-unprotect
expect_rejection ct-delete-protected ct-delete
expect_rejection ct-extra-change ct-unprotect
expect_rejection ct-extra-change ct-delete
expect_rejection ct-delete-extra-resource ct-delete

echo "plan policy fixtures passed"
