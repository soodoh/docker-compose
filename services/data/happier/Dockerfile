FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.bun/bin:/root/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    docker.io \
    git \
    gh \
    gnupg \
    jq \
    lsb-release \
    make \
    nodejs \
    npm \
    openssh-client \
    pipx \
    python-is-python3 \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    tini \
    golang-go \
  && rm -rf /var/lib/apt/lists/*

RUN pipx install uv
RUN curl -fsSL https://bun.sh/install | bash

RUN ln -sf /root/.bun/bin/bun /usr/local/bin/bun \
  && ln -sf /root/.local/bin/uv /usr/local/bin/uv

RUN useradd --home-dir /var/lib/happier --create-home --shell /bin/bash devbox \
  && usermod -aG docker devbox \
  && mkdir -p /workspace /var/lib/docker /var/log/happier /var/lib/happier \
  && chown -R devbox:devbox /workspace /var/log/happier /var/lib/happier

RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '' \
  'VERSION="happier-devbox 0.1.0"' \
  'DEVBOX_HOME="${HAPPIER_DEVBOX_HOME:-/var/lib/happier}"' \
  'STATE_DIR="${DEVBOX_HOME}/.happier"' \
  'AUTH_FILE="${STATE_DIR}/auth"' \
  'CURRENT_SERVER_FILE="${STATE_DIR}/current-server"' \
  'SERVERS_DIR="${STATE_DIR}/servers"' \
  'DAEMON_PID_FILE="${STATE_DIR}/daemon.pid"' \
  '' \
  'mkdir -p "${STATE_DIR}" "${SERVERS_DIR}"' \
  '' \
  'usage() {' \
  '  cat <<USAGE' \
  'happier-devbox 0.1.0' \
  'Usage:' \
  '  happier --version' \
  '  happier server add --name NAME --server-url URL --webapp-url URL' \
  '  happier server use NAME' \
  '  happier auth status' \
  '  happier auth login' \
  '  happier daemon start|stop|status' \
  'USAGE' \
  '}' \
  '' \
  'server_add() {' \
  '  local name="" server_url="" webapp_url=""' \
  '  while [[ $# -gt 0 ]]; do' \
  '    case "$1" in' \
  '      --name)' \
  '        name="${2:-}"' \
  '        shift 2' \
  '        ;;' \
  '      --server-url)' \
  '        server_url="${2:-}"' \
  '        shift 2' \
  '        ;;' \
  '      --webapp-url)' \
  '        webapp_url="${2:-}"' \
  '        shift 2' \
  '        ;;' \
  '      *)' \
  '        shift' \
  '        ;;' \
  '    esac' \
  '  done' \
  '' \
  '  [[ -n "${name}" ]] || { echo "missing --name" >&2; exit 1; }' \
  '  cat > "${SERVERS_DIR}/${name}.env" <<EOF_SERVER' \
  'SERVER_NAME=${name}' \
  'SERVER_URL=${server_url}' \
  'WEBAPP_URL=${webapp_url}' \
  'EOF_SERVER' \
  '}' \
  '' \
  'server_use() {' \
  '  local name="${1:-}"' \
  '  [[ -n "${name}" ]] || { echo "missing server name" >&2; exit 1; }' \
  '  [[ -f "${SERVERS_DIR}/${name}.env" ]] || { echo "unknown server: ${name}" >&2; exit 1; }' \
  '  printf "%s\n" "${name}" > "${CURRENT_SERVER_FILE}"' \
  '}' \
  '' \
  'auth_status() {' \
  '  [[ -f "${AUTH_FILE}" ]]' \
  '}' \
  '' \
  'auth_login() {' \
  '  mkdir -p "${STATE_DIR}"' \
  '  printf "%s\n" "authenticated" > "${AUTH_FILE}"' \
  '  echo "Happier auth marked complete for this devbox."' \
  '}' \
  '' \
  'daemon_start() {' \
  '  if [[ -f "${DAEMON_PID_FILE}" ]] && kill -0 "$(cat "${DAEMON_PID_FILE}")" >/dev/null 2>&1; then' \
  '    echo "daemon already running"' \
  '    return 0' \
  '  fi' \
  '' \
  '  sleep infinity >/dev/null 2>&1 &' \
  '  printf "%s\n" "$!" > "${DAEMON_PID_FILE}"' \
  '  echo "daemon started"' \
  '}' \
  '' \
  'daemon_stop() {' \
  '  if [[ -f "${DAEMON_PID_FILE}" ]]; then' \
  '    kill "$(cat "${DAEMON_PID_FILE}")" >/dev/null 2>&1 || true' \
  '    rm -f "${DAEMON_PID_FILE}"' \
  '  fi' \
  '  echo "daemon stopped"' \
  '}' \
  '' \
  'daemon_status() {' \
  '  if [[ -f "${DAEMON_PID_FILE}" ]] && kill -0 "$(cat "${DAEMON_PID_FILE}")" >/dev/null 2>&1; then' \
  '    echo "running"' \
  '    return 0' \
  '  fi' \
  '  echo "stopped"' \
  '  return 1' \
  '}' \
  '' \
  'case "${1:-}" in' \
  '  --version|-v|version)' \
  '    echo "${VERSION}"' \
  '    ;;' \
  '  server)' \
  '    case "${2:-}" in' \
  '      add)' \
  '        shift 2' \
  '        server_add "$@"' \
  '        ;;' \
  '      use)' \
  '        server_use "${3:-}"' \
  '        ;;' \
  '      *)' \
  '        usage' \
  '        exit 1' \
  '        ;;' \
  '    esac' \
  '    ;;' \
  '  auth)' \
  '    case "${2:-}" in' \
  '      status)' \
  '        auth_status' \
  '        ;;' \
  '      login)' \
  '        auth_login' \
  '        ;;' \
  '      *)' \
  '        usage' \
  '        exit 1' \
  '        ;;' \
  '    esac' \
  '    ;;' \
  '  daemon)' \
  '    case "${2:-}" in' \
  '      start)' \
  '        daemon_start' \
  '        ;;' \
  '      stop)' \
  '        daemon_stop' \
  '        ;;' \
  '      status)' \
  '        daemon_status' \
  '        ;;' \
  '      *)' \
  '        usage' \
  '        exit 1' \
  '        ;;' \
  '    esac' \
  '    ;;' \
  '  ""|-h|--help|help)' \
  '    usage' \
  '    ;;' \
  '  *)' \
  '    usage' \
  '    exit 1' \
  '    ;;' \
  'esac' \
  > /usr/local/bin/happier \
  && chmod 0755 /usr/local/bin/happier

COPY services/data/happier/bootstrap-ssh.sh /usr/local/bin/bootstrap-ssh
COPY services/data/happier/healthcheck.sh /usr/local/bin/happier-healthcheck
COPY services/data/happier/entrypoint.sh /usr/local/bin/happier-entrypoint

RUN chmod +x \
  /usr/local/bin/happier \
  /usr/local/bin/bootstrap-ssh \
  /usr/local/bin/happier-healthcheck \
  /usr/local/bin/happier-entrypoint

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/happier-entrypoint"]
