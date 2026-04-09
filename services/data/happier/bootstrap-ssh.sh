#!/usr/bin/env bash
set -euo pipefail

DEVBOX_USER="${HAPPIER_DEVBOX_USER:-devbox}"
DEVBOX_HOME="${HAPPIER_DEVBOX_HOME:-/var/lib/happier}"
SSH_DIR="${DEVBOX_HOME}/.ssh"
KNOWN_HOSTS_FALLBACK="/usr/local/share/happier/github_known_hosts"

install -d -m 700 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" "${SSH_DIR}"

copy_secret() {
  local source_path="$1"
  local destination_path="$2"
  local mode="$3"

  if [[ -s "${source_path}" ]]; then
    install -m "${mode}" -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" "${source_path}" "${destination_path}"
  elif [[ -e "${destination_path}" ]]; then
    return 0
  else
    install -m "${mode}" -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" /dev/null "${destination_path}"
  fi
}

copy_secret /run/secrets/github_ssh_key "${SSH_DIR}/id_ed25519" 600
copy_secret /run/secrets/github_ssh_key.pub "${SSH_DIR}/id_ed25519.pub" 644

if [[ -s /run/secrets/known_hosts ]]; then
  install -m 644 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" /run/secrets/known_hosts "${SSH_DIR}/known_hosts"
elif [[ -s "${KNOWN_HOSTS_FALLBACK}" && ! -s "${SSH_DIR}/known_hosts" ]]; then
  install -m 644 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" "${KNOWN_HOSTS_FALLBACK}" "${SSH_DIR}/known_hosts"
elif [[ ! -e "${SSH_DIR}/known_hosts" ]]; then
  install -m 644 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" /dev/null "${SSH_DIR}/known_hosts"
fi

cat > "${SSH_DIR}/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF

chown "${DEVBOX_USER}:${DEVBOX_USER}" "${SSH_DIR}/config"
chmod 600 "${SSH_DIR}/config"
