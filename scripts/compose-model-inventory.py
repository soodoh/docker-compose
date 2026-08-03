#!/usr/bin/env python3
"""Emit a secret-free desired or running Docker Compose model inventory."""

from argparse import ArgumentParser, Namespace
import hashlib
import json
from pathlib import Path
import subprocess
from typing import Any


def stable_hash(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def mapped_bind_source(
    source: object, artifact_root: Path, bind_root_override: Path | None
) -> object:
    if not isinstance(source, str) or bind_root_override is None:
        return source
    try:
        relative_source = Path(source).resolve().relative_to(artifact_root)
    except ValueError:
        return source
    return str(bind_root_override.resolve() / relative_source)


def run_json(command: list[str]) -> Any:
    result = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return json.loads(result.stdout)


def desired_inventory(args: Namespace) -> dict[str, object]:
    artifact_root = args.artifact_root.resolve()
    model = run_json(
        [
            "/usr/bin/docker",
            "compose",
            "--project-name",
            args.project_name,
            "--project-directory",
            str(args.project_directory.resolve()),
            "--env-file",
            str(args.env_file.resolve()),
            "--file",
            str(artifact_root / "docker-compose.yml"),
            "config",
            "--format",
            "json",
        ]
    )

    services = {}
    for service_name, service in sorted(model.get("services", {}).items()):
        mounts = service.get("volumes") or []
        healthcheck = service.get("healthcheck")
        services[service_name] = {
            "image": service.get("image"),
            "ports": sorted(
                (
                    {
                        "host_ip": port.get("host_ip"),
                        "published": port.get("published"),
                        "target": port.get("target"),
                        "protocol": port.get("protocol"),
                        "mode": port.get("mode"),
                    }
                    for port in service.get("ports") or []
                ),
                key=lambda port: json.dumps(port, sort_keys=True),
            ),
            "binds": sorted(
                (
                    {
                        "source": mapped_bind_source(
                            mount.get("source"), artifact_root, args.bind_root_override
                        ),
                        "target": mount.get("target"),
                        "read_only": mount.get("read_only", False),
                    }
                    for mount in mounts
                    if mount.get("type") == "bind"
                ),
                key=lambda mount: json.dumps(mount, sort_keys=True),
            ),
            "volumes": sorted(
                (
                    {
                        "source": mount.get("source"),
                        "target": mount.get("target"),
                        "read_only": mount.get("read_only", False),
                    }
                    for mount in mounts
                    if mount.get("type") == "volume"
                ),
                key=lambda mount: json.dumps(mount, sort_keys=True),
            ),
            "devices": sorted(
                (
                    {
                        "source": device.get("source"),
                        "target": device.get("target"),
                        "permissions": device.get("permissions"),
                    }
                    for device in service.get("devices") or []
                ),
                key=lambda device: json.dumps(device, sort_keys=True),
            ),
            "network_mode": service.get("network_mode"),
            "networks": sorted((service.get("networks") or {}).keys()),
            "healthcheck_sha256": stable_hash(healthcheck) if healthcheck else None,
        }

    volumes = sorted((model.get("volumes") or {}).keys())
    networks = {
        name: {
            "name": network.get("name"),
            "driver": network.get("driver"),
            "external": network.get("external", False),
        }
        for name, network in sorted((model.get("networks") or {}).items())
    }
    return {
        "kind": "desired",
        "project_name": args.project_name,
        "service_count": len(services),
        "volume_count": len(volumes),
        "services": services,
        "volumes": volumes,
        "networks": networks,
    }


def runtime_inventory(args: Namespace) -> dict[str, object]:
    ids_result = subprocess.run(
        [
            "/usr/bin/docker",
            "ps",
            "--all",
            "--quiet",
            "--filter",
            f"label=com.docker.compose.project={args.project_name}",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    container_ids = [line for line in ids_result.stdout.splitlines() if line]
    inspected = run_json(["/usr/bin/docker", "inspect", *container_ids]) if container_ids else []

    services = {}
    running_count = 0
    for container in inspected:
        labels = container.get("Config", {}).get("Labels") or {}
        service_name = labels.get("com.docker.compose.service")
        if not service_name:
            continue
        state = container.get("State") or {}
        if state.get("Running"):
            running_count += 1
        host_config = container.get("HostConfig") or {}
        mounts = container.get("Mounts") or []
        healthcheck = (container.get("Config") or {}).get("Healthcheck")
        network_settings = container.get("NetworkSettings") or {}
        services[service_name] = {
            "container_name": (container.get("Name") or "").removeprefix("/"),
            "running": bool(state.get("Running")),
            "health": (state.get("Health") or {}).get("Status"),
            "image": (container.get("Config") or {}).get("Image"),
            "image_id": container.get("Image"),
            "ports": host_config.get("PortBindings") or {},
            "binds": sorted(
                (
                    {
                        "source": mount.get("Source"),
                        "target": mount.get("Destination"),
                        "read_only": not mount.get("RW", False),
                    }
                    for mount in mounts
                    if mount.get("Type") == "bind"
                ),
                key=lambda mount: json.dumps(mount, sort_keys=True),
            ),
            "volumes": sorted(
                (
                    {
                        "source": mount.get("Name"),
                        "target": mount.get("Destination"),
                        "read_only": not mount.get("RW", False),
                    }
                    for mount in mounts
                    if mount.get("Type") == "volume"
                ),
                key=lambda mount: json.dumps(mount, sort_keys=True),
            ),
            "devices": sorted(
                (
                    {
                        "source": device.get("PathOnHost"),
                        "target": device.get("PathInContainer"),
                        "permissions": device.get("CgroupPermissions"),
                    }
                    for device in host_config.get("Devices") or []
                ),
                key=lambda device: json.dumps(device, sort_keys=True),
            ),
            "network_mode": host_config.get("NetworkMode"),
            "networks": sorted((network_settings.get("Networks") or {}).keys()),
            "healthcheck_sha256": stable_hash(healthcheck) if healthcheck else None,
        }

    volume_result = subprocess.run(
        [
            "/usr/bin/docker",
            "volume",
            "ls",
            "--quiet",
            "--filter",
            f"label=com.docker.compose.project={args.project_name}",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    project_volumes = sorted(line for line in volume_result.stdout.splitlines() if line)
    return {
        "kind": "runtime",
        "project_name": args.project_name,
        "container_count": len(services),
        "running_count": running_count,
        "project_volume_count": len(project_volumes),
        "project_volumes": project_volumes,
        "services": dict(sorted(services.items())),
    }


def parse_args() -> Namespace:
    parser = ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    desired = subparsers.add_parser("desired")
    desired.add_argument("--artifact-root", required=True, type=Path)
    desired.add_argument("--project-directory", required=True, type=Path)
    desired.add_argument("--env-file", required=True, type=Path)
    desired.add_argument("--project-name", default="docker-compose")
    desired.add_argument("--bind-root-override", type=Path)
    desired.add_argument("--output", type=Path)
    runtime = subparsers.add_parser("runtime")
    runtime.add_argument("--project-name", default="docker-compose")
    runtime.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    inventory = desired_inventory(args) if args.command == "desired" else runtime_inventory(args)
    encoded = json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n"
    if args.output is None:
        print(encoded, end="")
    else:
        if args.output.exists():
            raise SystemExit("refusing to overwrite an existing inventory output")
        args.output.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
