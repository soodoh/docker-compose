#!/usr/bin/env python3
"""Write a root-only, secret-free Docker Compose dry-run action plan."""

from argparse import ArgumentParser
import json
import os
from pathlib import Path
import re
import subprocess


ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
ACTION_PATTERN = re.compile(
    r"Container\s+([a-z0-9-]+)\s+"
    r"(Creating|Created|Create|Recreated|Recreate|Removing|Removed|Remove|Starting|Started|Start|Stopping|Stopped|Stop)\b"
)


def normalized_compose_content(
    project_name: str,
    project_directory: Path,
    env_file: Path,
    compose_file: Path,
    bind_root_override: Path,
) -> str:
    result = subprocess.run(
        [
            "/usr/bin/docker",
            "compose",
            "--project-name",
            project_name,
            "--project-directory",
            str(project_directory),
            "--env-file",
            str(env_file),
            "--file",
            str(compose_file),
            "config",
            "--format",
            "json",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    model = json.loads(result.stdout)
    project_root = project_directory.resolve()
    for service in (model.get("services") or {}).values():
        for mount in service.get("volumes") or []:
            if mount.get("type") != "bind" or not isinstance(mount.get("source"), str):
                continue
            try:
                relative = Path(mount["source"]).resolve().relative_to(project_root)
            except ValueError:
                continue
            mount["source"] = str(bind_root_override.resolve() / relative)
    return json.dumps(model, sort_keys=True, separators=(",", ":")) + "\n"


def write_private_new_file(path: Path, content: str) -> None:
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
    )
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--project-directory", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--compose-file", required=True, type=Path)
    parser.add_argument("--bind-root-override", type=Path)
    parser.add_argument("--normalized-output", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    dry_run_file = args.compose_file
    dry_run_project_directory = args.project_directory
    normalized_input = None
    if args.bind_root_override is not None:
        normalized_input = normalized_compose_content(
            args.project_name,
            args.project_directory,
            args.env_file,
            args.compose_file,
            args.bind_root_override,
        )
        dry_run_project_directory = args.bind_root_override
        if args.normalized_output is None:
            dry_run_file = Path("-")
        else:
            write_private_new_file(args.normalized_output, normalized_input)
            dry_run_file = args.normalized_output
            normalized_input = None

    result = subprocess.run(
        [
            "/usr/bin/docker",
            "compose",
            "--ansi",
            "never",
            "--dry-run",
            "--project-name",
            args.project_name,
            "--project-directory",
            str(dry_run_project_directory),
            "--env-file",
            str(args.env_file),
            "--file",
            str(dry_run_file),
            "create",
            "--no-build",
            "--pull",
            "never",
        ],
        check=True,
        input=normalized_input,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    output = ANSI_PATTERN.sub("", result.stdout + result.stderr)
    actions = [
        {"service": service, "action": action}
        for service, action in ACTION_PATTERN.findall(output)
    ]
    report = {
        "recreate_services": sorted(
            {entry["service"] for entry in actions if entry["action"] == "Recreate"}
        ),
        "forbidden_actions": [
            entry
            for entry in actions
            if entry["action"] in {"Create", "Creating", "Created", "Remove", "Removing", "Removed"}
        ],
        "action_count": len(actions),
    }
    write_private_new_file(
        args.output,
        json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n",
    )


if __name__ == "__main__":
    main()
