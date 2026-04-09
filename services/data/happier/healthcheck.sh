#!/usr/bin/env bash
set -euo pipefail

if ! docker info >/dev/null 2>&1; then
  exit 1
fi

auth_status_output="$(happier auth status 2>&1 || true)"
if printf '%s\n' "${auth_status_output}" | grep -q 'Not authenticated'; then
  exit 0
fi

daemon_status_output="$(happier daemon status 2>&1 || true)"
if printf '%s\n' "${daemon_status_output}" | grep -q 'Daemon is running'; then
  exit 0
fi

exit 1
