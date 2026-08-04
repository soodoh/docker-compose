#!/usr/bin/env python3
"""Create only declared fresh Compose volumes and required volume subpaths."""

from argparse import ArgumentParser
import json
from pathlib import Path, PurePosixPath
import subprocess
import tempfile
import sys


def fail(reason: str) -> None:
    print(f"recovery_volume_prepare=failed reason={reason}", file=sys.stderr)
    raise SystemExit(1)


def run(arguments: list[str], *, output: bool = False) -> str:
    try:
        result = subprocess.run(
            arguments,
            check=True,
            stdout=subprocess.PIPE if output else subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return result.stdout if output else ""
    except subprocess.SubprocessError:
        fail("docker_command_error")


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--project-directory", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--compose-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    compose = [
        "docker",
        "compose",
        "--project-name",
        args.project,
        "--project-directory",
        str(args.project_directory),
        "--env-file",
        str(args.env_file),
        "--file",
        str(args.compose_file),
    ]
    try:
        model = json.loads(run([*compose, "config", "--format", "json"], output=True))
    except json.JSONDecodeError:
        fail("compose_model_error")

    volumes = model.get("volumes")
    services = model.get("services")
    if not isinstance(volumes, dict) or not isinstance(services, dict):
        fail("compose_model_schema")

    engine_names: dict[str, str] = {}
    volume_records: dict[str, dict[str, object]] = {}
    for logical_name, definition in sorted(volumes.items()):
        if not isinstance(definition, dict):
            fail("volume_definition_schema")
        if definition.get("external"):
            fail("external_volume_forbidden")
        engine_name = definition.get("name") or f"{args.project}_{logical_name}"
        if not isinstance(engine_name, str):
            fail("volume_name_schema")
        existing = run(
            ["docker", "volume", "ls", "--quiet", "--filter", f"name=^{engine_name}$"],
            output=True,
        ).splitlines()
        if engine_name in existing:
            fail("preexisting_volume_name")
        run(
            [
                "docker",
                "volume",
                "create",
                "--label",
                f"com.docker.compose.project={args.project}",
                "--label",
                f"com.docker.compose.volume={logical_name}",
                engine_name,
            ]
        )
        engine_names[logical_name] = engine_name
        inspected = json.loads(
            run(["docker", "volume", "inspect", engine_name], output=True)
        )[0]
        labels = inspected.get("Labels") or {}
        if (
            inspected.get("Name") != engine_name
            or labels.get("com.docker.compose.project") != args.project
            or labels.get("com.docker.compose.volume") != logical_name
        ):
            fail("created_volume_identity_error")
        volume_records[logical_name] = {
            "logical_name": logical_name,
            "engine_name": engine_name,
            "mountpoint": inspected.get("Mountpoint"),
            "created_at": inspected.get("CreatedAt"),
        }

    subpaths: dict[str, set[PurePosixPath]] = {name: set() for name in volumes}
    for service in services.values():
        if not isinstance(service, dict):
            fail("service_schema")
        for mount in service.get("volumes") or []:
            if not isinstance(mount, dict) or mount.get("type") != "volume":
                continue
            source = mount.get("source")
            volume_options = mount.get("volume") or {}
            subpath = volume_options.get("subpath")
            if source not in subpaths or not subpath:
                continue
            relative = PurePosixPath(subpath)
            if relative.is_absolute() or ".." in relative.parts:
                fail("unsafe_volume_subpath")
            subpaths[source].add(relative)

    for logical_name, paths in subpaths.items():
        if not paths:
            continue
        mountpoint_value = volume_records[logical_name].get("mountpoint")
        if not isinstance(mountpoint_value, str) or not mountpoint_value:
            fail("created_volume_mountpoint_error")
        mountpoint = Path(mountpoint_value)
        for relative in sorted(paths, key=lambda item: item.as_posix()):
            destination = mountpoint.joinpath(*relative.parts)
            destination.mkdir(parents=True, exist_ok=True, mode=0o755)

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    document = {
        "schema": 1,
        "project": args.project,
        "volumes": [volume_records[name] for name in sorted(volume_records)],
    }
    with tempfile.NamedTemporaryFile("w", dir=output.parent, delete=False) as stream:
        json.dump(document, stream, sort_keys=True, separators=(",", ":"))
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.chmod(0o600)
    temporary.replace(output)

    print(
        f"recovery_volume_prepare=verified volumes={len(volumes)} "
        f"subpaths={sum(len(paths) for paths in subpaths.values())}"
    )


if __name__ == "__main__":
    main()
