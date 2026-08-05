#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
policy="$root/inspect-plan.py"
fixtures="$root/fixtures"

python3 "$policy" "$fixtures/noop.json"
python3 "$policy" "$fixtures/adopt-import.json" --mode adopt
python3 "$policy" "$fixtures/adopt-noop.json" --mode adopt-or-noop
python3 "$policy" "$fixtures/recovery-create.json" --mode recovery
python3 "$policy" "$fixtures/network-migration.json" --mode network-migration
python3 "$policy" "$fixtures/ct-decommission.json" --mode ct-decommission
python3 "$policy" "$fixtures/ct-unprotect.json" --mode ct-decommission
python3 "$policy" "$fixtures/protection-enable.json"
python3 "$policy" "$fixtures/qualification-create.json" --mode qualification
python3 "$policy" "$fixtures/qualification-delete.json" --mode qualification

for fixture in delete replace protection-disable recovery-wrong-vm recovery-update \
  network-migration-extra-change mapping-device-change ct-wrong-id ct-delete-protected \
  qualification-wrong-resource; do
  mode=normal
  case "$fixture" in
    recovery-wrong-vm|recovery-update) mode=recovery ;;
    network-migration-extra-change|mapping-device-change) mode=network-migration ;;
    ct-wrong-id|ct-delete-protected) mode=ct-decommission ;;
    qualification-wrong-resource) mode=qualification ;;
  esac
  if python3 "$policy" "$fixtures/$fixture.json" --mode "$mode" >/dev/null 2>&1; then
    echo "expected policy rejection for $fixture" >&2
    exit 1
  fi
done

echo "plan policy fixtures passed"
