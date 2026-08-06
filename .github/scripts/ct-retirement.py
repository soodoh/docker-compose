#!/usr/bin/env python3
"""Validate the contract-driven legacy container retirement lifecycle."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import sys
from typing import Any

STAGES = {"protected", "unprotected", "retired"}
OPERATIONS = {"none", "unprotect", "delete"}
CONFIRMATION_ENVIRONMENT = "PROXMOX_CT_DECOMMISSION_CONFIRMATION"
CONFIRMATION_SHA256 = "6aef61a66bc191b96d854e1c34be3a8c79178bd1ae864a2cdc5bc8700c5eff8c"
TRANSITION_OPERATIONS = {
    ("protected", "protected"): "none",
    ("protected", "unprotected"): "unprotect",
    ("unprotected", "protected"): "none",
    ("unprotected", "unprotected"): "none",
    ("unprotected", "retired"): "delete",
    ("retired", "retired"): "none",
}


class RetirementError(ValueError):
    """Raised when a retirement lifecycle invariant is not met."""


def contract_stage(path: Path) -> str:
    target = ("proxmox", "legacy_container", "retirement_stage")
    legacy_target = ("proxmox", "legacy_container", "protected")
    ancestors: list[tuple[int, str]] = []
    legacy_protected = False
    for line in path.read_text().splitlines():
        match = re.match(r"^( *)([A-Za-z_][A-Za-z0-9_]*):(?:[ ]+(.*))?$", line)
        if not match:
            continue
        indent = len(match.group(1))
        key = match.group(2)
        value = match.group(3)
        while ancestors and indent <= ancestors[-1][0]:
            ancestors.pop()
        current_path = tuple(entry[1] for entry in ancestors) + (key,)
        if current_path == target:
            stage = (value or "").split(" #", 1)[0].strip().strip("\"'")
            if stage not in STAGES:
                raise RetirementError("contract retirement_stage is invalid")
            return stage
        if current_path == legacy_target:
            legacy_protected = (value or "").split(" #", 1)[0].strip() == "true"
        if value is None:
            ancestors.append((indent, key))
    if legacy_protected:
        return "protected"
    raise RetirementError("contract retirement_stage is missing")


def operation_matches_stage(operation: str, stage: str) -> bool:
    if operation not in OPERATIONS or stage not in STAGES:
        return False
    return operation == "none" or (operation, stage) in {
        ("unprotect", "unprotected"),
        ("delete", "retired"),
    }


def confirmation_matches() -> bool:
    supplied = os.environ.get(CONFIRMATION_ENVIRONMENT, "")
    supplied_sha256 = hashlib.sha256(supplied.encode()).hexdigest()
    return bool(supplied) and hmac.compare_digest(supplied_sha256, CONFIRMATION_SHA256)


def confirmation_required(operation: str, stage: str) -> bool:
    return operation != "none" or stage != "protected"


def transition_operation(base_stage: str, head_stage: str) -> str:
    try:
        return TRANSITION_OPERATIONS[(base_stage, head_stage)]
    except KeyError as error:
        raise RetirementError("retirement_stage transition is not permitted") from error


def verify_manifest_fields(manifest: Any, operation: str, stage: str) -> None:
    if not isinstance(manifest, dict) or manifest.get("version") != 2:
        raise RetirementError("saved-plan manifest version is invalid")
    if manifest.get("ct_retirement_operation") != operation:
        raise RetirementError("saved-plan manifest retirement operation mismatch")
    if manifest.get("retirement_stage") != stage:
        raise RetirementError("saved-plan manifest retirement stage mismatch")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    operation = subparsers.add_parser("validate-operation")
    operation.add_argument("--contract", type=Path, required=True)
    operation.add_argument("--operation", choices=sorted(OPERATIONS), required=True)

    transition = subparsers.add_parser("transition")
    transition.add_argument("--base-contract", type=Path, required=True)
    transition.add_argument("--head-contract", type=Path, required=True)
    transition.add_argument("--github-output", type=Path)

    manifest = subparsers.add_parser("verify-manifest")
    manifest.add_argument("--manifest", type=Path, required=True)
    manifest.add_argument("--contract", type=Path, required=True)
    manifest.add_argument("--operation", choices=sorted(OPERATIONS), required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "validate-operation":
            stage = contract_stage(args.contract)
            if not operation_matches_stage(args.operation, stage):
                raise RetirementError("retirement operation does not match the contract stage")
            if confirmation_required(args.operation, stage) and not confirmation_matches():
                raise RetirementError("exact CT retirement confirmation is required")
            return 0

        if args.command == "transition":
            operation = transition_operation(
                contract_stage(args.base_contract), contract_stage(args.head_contract)
            )
            if args.github_output:
                with args.github_output.open("a") as output:
                    output.write(f"operation={operation}\n")
            else:
                print(operation)
            return 0

        stage = contract_stage(args.contract)
        if not operation_matches_stage(args.operation, stage):
            raise RetirementError("retirement operation does not match the contract stage")
        verify_manifest_fields(json.loads(args.manifest.read_text()), args.operation, stage)
        return 0
    except (OSError, json.JSONDecodeError, RetirementError) as error:
        print(f"CT retirement validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
