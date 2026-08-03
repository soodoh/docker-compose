#!/usr/bin/env python3
"""Write a root-only, secret-free Docker Compose dry-run action plan."""

from argparse import ArgumentParser
import json
from pathlib import Path
import re
import subprocess
import tempfile

ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
ACTION_PATTERN = re.compile(
    r"Container\s+([a-z0-9-]+)\s+"
    r"(Creating|Created|Create|Recreated|Recreate|Removing|Removed|Remove|Starting|Started|Start|Stopping|Stopped|Stop)\b"
)


def normalized_compose_file(
    project_name: str,
    project_directory: Path,
    env_file: Path,
    compose_file: Path,
    bind_root_override: Path,
    output_path: Path | None = None,
) -> Path:
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

    content = json.dumps(model, sort_keys=True, separators=(",", ":")) + "\n"
    if output_path is not None:
        output_path.write_text(content, encoding="utf-8")
        output_path.chmod(0o600)
        return output_path

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix="docker-compose-normalized-",
        suffix=".json",
        dir="/run",
        delete=False,
    ) as handle:
        handle.write(content)
        return Path(handle.name)


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

    normalized_file = None
    dry_run_file = args.compose_file
    dry_run_project_directory = args.project_directory
    try:
        if args.bind_root_override is not None:
            normalized_file = normalized_compose_file(
                args.project_name,
                args.project_directory,
                args.env_file,
                args.compose_file,
                args.bind_root_override,
                args.normalized_output,
            )
            dry_run_file = normalized_file
            dry_run_project_directory = args.bind_root_override
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
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    finally:
        if normalized_file is not None and args.normalized_output is None:
            normalized_file.unlink(missing_ok=True)
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
    args.output.write_text(
        json.dumps(report, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    args.output.chmod(0o600)


if __name__ == "__main__":
    main()
