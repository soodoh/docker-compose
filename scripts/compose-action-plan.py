#!/usr/bin/env python3
"""Write a root-only, secret-free Docker Compose dry-run action plan."""

from argparse import ArgumentParser
import json
from pathlib import Path
import re
import subprocess

ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
ACTION_PATTERN = re.compile(
    r"Container\s+([a-z0-9-]+)\s+"
    r"(Creating|Created|Create|Recreated|Recreate|Removing|Removed|Remove|Starting|Started|Start|Stopping|Stopped|Stop)\b"
)


def main() -> None:
    parser = ArgumentParser()
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--project-directory", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--compose-file", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

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
            str(args.project_directory),
            "--env-file",
            str(args.env_file),
            "--file",
            str(args.compose_file),
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
