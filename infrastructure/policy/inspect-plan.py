#!/usr/bin/env python3
"""Reject unsafe OpenTofu plans before any apply."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

SENSITIVE_FIELDS = {
    "vm_id",
    "vmid",
    "mac_address",
    "protection",
    "disk",
    "hostpci",
    "usb",
    "network_device",
    "path_in_datastore",
}
STORAGE_RESOURCE_MARKERS = ("zfs", "filesystem", "disk", "mount", "storage")
NETWORK_RESOURCE_MARKERS = ("firewall", "network", "acl", "ruleset", "federated_identity")
RECOVERY_ADDRESSES = {
    "proxmox_download_file.arch_recovery_image[0]",
    'proxmox_hardware_mapping_pci.device["coral"]',
    'proxmox_hardware_mapping_pci.device["gpu"]',
    'proxmox_hardware_mapping_pci.device["gpu_audio"]',
    'proxmox_hardware_mapping_usb.device["bluetooth"]',
    'proxmox_hardware_mapping_usb.device["zigbee"]',
    'proxmox_hardware_mapping_usb.device["zwave"]',
    "proxmox_virtual_environment_vm.arch",
}
MAPPING_ADDRESSES = RECOVERY_ADDRESSES - {
    "proxmox_download_file.arch_recovery_image[0]",
    "proxmox_virtual_environment_vm.arch",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan_json", type=Path)
    parser.add_argument(
        "--mode",
        choices=("normal", "adopt", "adopt-or-noop", "recovery", "ct-decommission", "network-migration"),
        default="normal",
    )
    parser.add_argument("--allow-change-file", type=Path)
    return parser.parse_args()


def changed_keys(before: Any, after: Any, prefix: tuple[str, ...] = ()) -> set[tuple[str, ...]]:
    if isinstance(before, dict) and isinstance(after, dict):
        result: set[tuple[str, ...]] = set()
        for key in before.keys() | after.keys():
            result |= changed_keys(before.get(key), after.get(key), prefix + (str(key),))
        return result
    if before != after:
        return {prefix}
    return set()

def value_at_path(value: Any, path: tuple[str, ...]) -> Any:
    current = value
    for part in path:
        if isinstance(current, dict):
            current = current.get(part)
        elif isinstance(current, list) and part.isdigit() and int(part) < len(current):
            current = current[int(part)]
        else:
            return None
    return current


def safe_protection_enable(before: Any, after: Any, path: tuple[str, ...]) -> bool:
    return path and path[-1] == "protection" and value_at_path(before, path) is False and value_at_path(after, path) is True


def complete_mapping(after: Any, expected_name: str) -> bool:
    if not isinstance(after, dict) or after.get("name") != expected_name:
        return False
    mapping = after.get("map")
    return isinstance(mapping, list) and len(mapping) > 0 and all(
        isinstance(entry, dict)
        and isinstance(entry.get("id"), str)
        and bool(entry.get("id"))
        and isinstance(entry.get("node"), str)
        and bool(entry.get("node"))
        for entry in mapping
    )


def only_hardware_mappings(entries: Any, raw_field: str) -> bool:
    return isinstance(entries, list) and len(entries) > 0 and all(
        isinstance(entry, dict)
        and isinstance(entry.get("mapping"), str)
        and bool(entry.get("mapping"))
        and entry.get(raw_field) in (None, "")
        for entry in entries
    )


def main() -> int:
    args = parse_args()
    plan = json.loads(args.plan_json.read_text())
    allow = set()
    if args.allow_change_file:
        allow = {line.strip() for line in args.allow_change_file.read_text().splitlines() if line.strip() and not line.startswith("#")}

    failures: list[str] = []
    observed_actions = 0
    observed_addresses: set[str] = set()
    for resource in plan.get("resource_changes", []):
        address = resource.get("address", "<unknown>")
        resource_type = resource.get("type", "")
        change = resource.get("change", {})
        actions = change.get("actions", [])
        importing = change.get("importing") is not None
        if actions in ([], ["no-op"], ["read"]) and not importing:
            continue
        observed_actions += 1
        observed_addresses.add(address)

        if args.mode in {"adopt", "adopt-or-noop"}:
            if not importing or any(action in actions for action in ("create", "update", "delete")):
                failures.append(f"{address}: adoption permits import-only actions")
            continue

        if args.mode == "recovery":
            recovery_addresses = RECOVERY_ADDRESSES
            if address not in recovery_addresses or actions != ["create"] or change.get("before") is not None:
                failures.append(f"{address}: recovery permits only expected fresh creates")
                continue
            after = change.get("after") or {}
            if address.startswith("proxmox_hardware_mapping_"):
                expected_name = address.split('["', 1)[1].split('"]', 1)[0]
                if not complete_mapping(after, expected_name):
                    failures.append(f"{address}: recovery requires a complete expected hardware mapping")
            elif address == "proxmox_download_file.arch_recovery_image[0]":
                if after.get("checksum_algorithm") != "sha256" or not after.get("checksum"):
                    failures.append(f"{address}: recovery image requires a SHA-256 checksum")
            elif address == "proxmox_virtual_environment_vm.arch":
                if (
                    after.get("vm_id") != 100
                    or after.get("protection") is not True
                    or not isinstance(after.get("disk"), list)
                    or len(after.get("disk")) < 2
                    or not only_hardware_mappings(after.get("hostpci"), "id")
                    or not only_hardware_mappings(after.get("usb"), "host")
                ):
                    failures.append(f"{address}: recovery requires protected VM 100 with complete disks and mappings")
            continue

        if args.mode == "network-migration":
            mapping_addresses = MAPPING_ADDRESSES
            vm_address = "proxmox_virtual_environment_vm.arch"
            if address not in mapping_addresses | {vm_address}:
                failures.append(f"{address}: hardware-mapping migration action is outside the allowlist")
                continue
            before = change.get("before") or {}
            after = change.get("after") or {}
            if address in mapping_addresses:
                expected_name = address.split('["', 1)[1].split('"]', 1)[0]
                if actions != ["create"] or change.get("before") is not None or not complete_mapping(after, expected_name):
                    failures.append(f"{address}: migration requires one complete new expected mapping")
                continue
            changed_roots = {path[0] for path in changed_keys(before, after) if path}
            if (
                actions != ["update"]
                or before.get("vm_id") != 100
                or after.get("vm_id") != 100
                or before.get("protection") is not True
                or after.get("protection") is not True
                or changed_roots != {"hostpci", "usb"}
                or not only_hardware_mappings(after.get("hostpci"), "id")
                or not only_hardware_mappings(after.get("usb"), "host")
            ):
                failures.append(f"{address}: migration permits only the complete VM 100 host-device mapping transition")
            continue

        if args.mode == "ct-decommission":
            is_target = address == "proxmox_virtual_environment_container.tailscale_gateway[0]"
            before = change.get("before") or {}
            after = change.get("after") or {}
            is_unprotect = (
                actions == ["update"]
                and before.get("vm_id") == 101
                and after.get("vm_id") == 101
                and changed_keys(before, after) == {("protection",)}
                and before.get("protection") is True
                and after.get("protection") is False
            )
            is_delete = (
                actions == ["delete"]
                and before.get("vm_id") == 101
                and before.get("protection") is False
                and change.get("after") is None
            )
            if not is_target or not (is_delete or is_unprotect):
                failures.append(f"{address}: CT mode permits only staged unprotection or deletion of unprotected CT 101")
            continue

        if "delete" in actions:
            failures.append(f"{address}: delete or replacement is forbidden")
            continue

        if address in allow:
            continue

        before = change.get("before")
        after = change.get("after")
        changed = changed_keys(before, after)
        sensitive = sorted(
            ".".join(path)
            for path in changed
            if any(part in SENSITIVE_FIELDS for part in path)
            and not safe_protection_enable(before, after, path)
        )
        if sensitive:
            failures.append(f"{address}: protected field change: {', '.join(sensitive)}")

        lower_type = resource_type.lower()
        if any(marker in lower_type for marker in STORAGE_RESOURCE_MARKERS):
            failures.append(f"{address}: storage mutation requires an explicit reviewed allowlist")
        if args.mode != "network-migration" and any(marker in lower_type for marker in NETWORK_RESOURCE_MARKERS):
            failures.append(f"{address}: network/control-plane mutation requires network-migration mode or an allowlist")

    if args.mode == "adopt" and observed_actions == 0:
        failures.append("adoption plan contains no import actions")
    if args.mode == "recovery" and observed_addresses != RECOVERY_ADDRESSES:
        failures.append("recovery plan must contain the complete expected fresh resource set")
    if (
        args.mode == "network-migration"
        and observed_addresses != MAPPING_ADDRESSES | {"proxmox_virtual_environment_vm.arch"}
    ):
        failures.append("hardware migration plan must contain all mappings and the VM transition")

    if failures:
        for failure in sorted(set(failures)):
            print(f"DENY: {failure}", file=sys.stderr)
        return 1
    print(f"plan policy passed: mode={args.mode} actions={observed_actions}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
