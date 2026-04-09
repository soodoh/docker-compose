#!/usr/bin/env bash
set -euo pipefail

DEVBOX_USER="${HAPPIER_DEVBOX_USER:-devbox}"
DEVBOX_HOME="${HAPPIER_DEVBOX_HOME:-/var/lib/happier}"
SERVER_NAME="${HAPPIER_SERVER_NAME:-default}"
SERVER_URL="${HAPPIER_SERVER_URL:-https://api.happier.dev}"
WEBAPP_URL="${HAPPIER_WEBAPP_URL:-https://app.happier.dev}"

if [[ $# -gt 0 ]]; then
  exec "$@"
fi

mkdir -p /var/run /var/log/happier "${DEVBOX_HOME}"
chown "${DEVBOX_USER}:${DEVBOX_USER}" "${DEVBOX_HOME}" /var/log/happier /workspace

if find /workspace -xdev \( ! -user "${DEVBOX_USER}" -o ! -group "${DEVBOX_USER}" \) -print -quit | grep -q .; then
  chown -R "${DEVBOX_USER}:${DEVBOX_USER}" /workspace
fi

dockerd --host=unix:///var/run/docker.sock --storage-driver=vfs \
  > >(tee -a /var/log/happier/dockerd.log) \
  2> >(tee -a /var/log/happier/dockerd.log >&2) &
DOCKERD_PID=$!

cleanup() {
  su - "${DEVBOX_USER}" -c "happier daemon stop" >/dev/null 2>&1 || true
  kill "${DOCKERD_PID}" >/dev/null 2>&1 || true
  wait "${DOCKERD_PID}" || true
}

trap cleanup EXIT INT TERM

auth_status_output="$(su - "${DEVBOX_USER}" -c "happier auth status" 2>&1 || true)"
is_authenticated=1
if printf '%s\n' "${auth_status_output}" | grep -q 'Not authenticated'; then
  is_authenticated=0
  echo "Happier is not linked yet. Run 'docker exec -it -u devbox happier-devbox happier auth login' after the container starts."
fi

for _ in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker info >/dev/null 2>&1
bootstrap-ssh

su - "${DEVBOX_USER}" -c "happier server add --name '${SERVER_NAME}' --server-url '${SERVER_URL}' --webapp-url '${WEBAPP_URL}' >/dev/null 2>&1 || true"
su - "${DEVBOX_USER}" -c "happier server use '${SERVER_NAME}'"

if [[ "${is_authenticated}" -eq 1 ]]; then
  su - "${DEVBOX_USER}" -c "happier daemon start"
fi

wait "${DOCKERD_PID}"
