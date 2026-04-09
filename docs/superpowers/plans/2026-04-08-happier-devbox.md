# Happier Devbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single-user Happier devbox service to this Docker Compose repo, with a persistent multi-repo workspace, SSH-based GitHub access, and Docker-in-Docker isolation for project workloads.

**Architecture:** Add a new `services/happier.yml` stack that builds a local `happier-devbox` image and persists three data areas: workspace, Happier state, and nested Docker state. The container runs an inner Docker daemon, bootstraps SSH credentials, and starts the Happier daemon against Happier Cloud without exposing any public inbound route.

**Tech Stack:** Docker Compose, Debian-based custom image, Docker-in-Docker, Happier CLI, SSH, GitHub, shell entrypoint scripts

---

## File Structure

- Modify: `docker-compose.yml`
  Add the new compose include for the Happier stack.

- Create: `services/happier.yml`
  Define the `happier-devbox` service, volumes, network, healthcheck, SSH mounts, and backup-relevant volume names.

- Modify: `services/infra.yml`
  Add the devbox home volume to the backup volume anchor and keep workspace and nested Docker state out of backups.

- Create: `services/data/happier/Dockerfile`
  Build the devbox image with Docker, Happier CLI, SSH tooling, and language runtimes.

- Create: `services/data/happier/entrypoint.sh`
  Start `dockerd`, wait for health, initialize SSH files, configure Happier Cloud server profile, and start the Happier daemon.

- Create: `services/data/happier/bootstrap-ssh.sh`
  Copy mounted SSH key material into the persisted Happier home with correct permissions and GitHub host trust.

- Create: `services/data/happier/healthcheck.sh`
  Verify the inner Docker daemon is usable.

- Create: `docs/happier-devbox.md`
  Document required local `.env` entries, first-run linking, clone workflow, nested Docker usage, and cleanup commands.

## Task 1: Wire the Compose Stack

**Files:**
- Modify: `docker-compose.yml`
- Create: `services/happier.yml`
- Modify: `services/infra.yml`

- [ ] **Step 1: Capture the current compose baseline**

Run:

```bash
docker compose config --quiet
```

Expected: command exits `0`.

- [ ] **Step 2: Add the Happier stack include to `docker-compose.yml`**

Update the include list so the new stack is loaded with the rest of the project:

```yaml
include:
  - ./services/openfit.yml
  - ./services/apps.yml
  - ./services/hass.yml
  - ./services/nextcloud.yml
  - ./services/servarr.yml
  - ./services/authentik.yml
  - ./services/infra.yml
  - ./services/happier.yml
```

- [ ] **Step 3: Create `services/happier.yml` with the isolated devbox service**

Create the file with a dedicated network, three persistent volumes, SSH secret-style mounts, and a Docker healthcheck:

```yaml
x-logging: &default-logging
  driver: json-file
  options:
    max-size: 10m
    max-file: 3

services:
  happier-devbox:
    build:
      context: ..
      dockerfile: ./services/data/happier/Dockerfile
    container_name: happier-devbox
    restart: unless-stopped
    privileged: true
    logging: *default-logging
    environment:
      TZ: $TZ
      HAPPIER_SERVER_NAME: ${HAPPIER_SERVER_NAME:-default}
      HAPPIER_SERVER_URL: ${HAPPIER_SERVER_URL:-https://api.happier.dev}
      HAPPIER_WEBAPP_URL: ${HAPPIER_WEBAPP_URL:-https://app.happier.dev}
      HAPPIER_DEVBOX_USER: devbox
      HAPPIER_DEVBOX_HOME: /var/lib/happier
      HAPPIER_WORKSPACE_DIR: /workspace
    volumes:
      - happier-workspace:/workspace
      - happier-home-data:/var/lib/happier
      - happier-docker-data:/var/lib/docker
      - ${HAPPIER_SSH_KEY_PATH}:/run/secrets/github_ssh_key:ro
      - ${HAPPIER_SSH_PUBLIC_KEY_PATH}:/run/secrets/github_ssh_key.pub:ro
      - ${HAPPIER_SSH_KNOWN_HOSTS_PATH}:/run/secrets/known_hosts:ro
    healthcheck:
      test: ["CMD", "/usr/local/bin/happier-healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 45s
    networks:
      - happier

volumes:
  happier-workspace:
  happier-home-data:
  happier-docker-data:

networks:
  happier:
    ipam:
      driver: default
      config:
        - subnet: "172.25.0.0/16"
```

- [ ] **Step 4: Add the devbox home volume to the backup anchor in `services/infra.yml`**

Add only the home/config volume to `x-backup-volumes`:

```yaml
x-backup-volumes: &backup-volumes
  - audiobookshelf-data:/backup/audiobookshelf-data:ro
  - authentik-data:/backup/authentik-data:ro
  - bookshelf-data:/backup/bookshelf-data:ro
  - caddy-data:/backup/caddy-data:ro
  - calibre-data:/backup/calibre-data:ro
  - calibre-web-data:/backup/calibre-web-data:ro
  - caro-tachidesk-data:/backup/caro-tachidesk-data:ro
  - ddns-updater-data:/backup/ddns-updater-data:ro
  - frigate-data:/backup/frigate-data:ro
  - gluetun-data:/backup/gluetun-data:ro
  - happier-home-data:/backup/happier-home-data:ro
  - jellyfin-data:/backup/jellyfin-data:ro
  - seerr-data:/backup/seerr-data:ro
```

Do not add `happier-workspace` or `happier-docker-data` to backups.

- [ ] **Step 5: Validate the compose graph**

Run:

```bash
touch /tmp/id_ed25519 /tmp/id_ed25519.pub /tmp/known_hosts
HAPPIER_SSH_KEY_PATH=/tmp/id_ed25519 \
HAPPIER_SSH_PUBLIC_KEY_PATH=/tmp/id_ed25519.pub \
HAPPIER_SSH_KNOWN_HOSTS_PATH=/tmp/known_hosts \
docker compose config > /tmp/happier-devbox.compose.yaml
rg -n "happier-devbox|happier-home-data|172.25.0.0/16" /tmp/happier-devbox.compose.yaml
```

Expected:

```text
services:
  happier-devbox:
volumes:
  happier-home-data:
subnet: 172.25.0.0/16
```

- [ ] **Step 6: Commit the compose wiring**

Run:

```bash
git add docker-compose.yml services/happier.yml services/infra.yml
git commit -m "feat: add happier devbox compose stack"
```

Expected: commit succeeds.

## Task 2: Build the Devbox Image and Runtime Scripts

**Files:**
- Create: `services/data/happier/Dockerfile`
- Create: `services/data/happier/entrypoint.sh`
- Create: `services/data/happier/bootstrap-ssh.sh`
- Create: `services/data/happier/healthcheck.sh`

- [ ] **Step 1: Create the Dockerfile with Docker, Happier, and the base toolchain**

Create `services/data/happier/Dockerfile`:

```dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/root/.bun/bin:/root/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gh \
    gnupg \
    lsb-release \
    jq \
    make \
    build-essential \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    golang-go \
    nodejs \
    npm \
    docker.io \
    docker-compose-plugin \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN pipx install uv
RUN curl -fsSL https://bun.sh/install | bash
RUN curl -fsSL https://happier.dev/install | bash

RUN ln -sf /root/.bun/bin/bun /usr/local/bin/bun \
  && ln -sf /root/.local/bin/happier /usr/local/bin/happier \
  && ln -sf /root/.local/bin/uv /usr/local/bin/uv

RUN useradd --home-dir /var/lib/happier --create-home --shell /bin/bash devbox \
  && usermod -aG docker devbox \
  && mkdir -p /workspace /var/lib/docker /var/log/happier /var/lib/happier \
  && chown -R devbox:devbox /workspace /var/log/happier /var/lib/happier

COPY services/data/happier/bootstrap-ssh.sh /usr/local/bin/bootstrap-ssh
COPY services/data/happier/healthcheck.sh /usr/local/bin/happier-healthcheck
COPY services/data/happier/entrypoint.sh /usr/local/bin/happier-entrypoint

RUN chmod +x /usr/local/bin/bootstrap-ssh \
  /usr/local/bin/happier-healthcheck \
  /usr/local/bin/happier-entrypoint

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/happier-entrypoint"]
```

- [ ] **Step 2: Add SSH bootstrap logic**

Create `services/data/happier/bootstrap-ssh.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DEVBOX_USER="${HAPPIER_DEVBOX_USER:-devbox}"
DEVBOX_HOME="${HAPPIER_DEVBOX_HOME:-/var/lib/happier}"
SSH_DIR="${DEVBOX_HOME}/.ssh"

install -d -m 700 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" "${SSH_DIR}"

install -m 600 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" /run/secrets/github_ssh_key "${SSH_DIR}/id_ed25519"
install -m 644 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" /run/secrets/github_ssh_key.pub "${SSH_DIR}/id_ed25519.pub"

if [[ -f /run/secrets/known_hosts ]]; then
  install -m 644 -o "${DEVBOX_USER}" -g "${DEVBOX_USER}" /run/secrets/known_hosts "${SSH_DIR}/known_hosts"
else
  ssh-keyscan github.com > "${SSH_DIR}/known_hosts"
  chown "${DEVBOX_USER}:${DEVBOX_USER}" "${SSH_DIR}/known_hosts"
  chmod 644 "${SSH_DIR}/known_hosts"
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
```

- [ ] **Step 3: Add the healthcheck and entrypoint**

Create `services/data/happier/healthcheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
docker info >/dev/null 2>&1
```

Create `services/data/happier/entrypoint.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DEVBOX_USER="${HAPPIER_DEVBOX_USER:-devbox}"
DEVBOX_HOME="${HAPPIER_DEVBOX_HOME:-/var/lib/happier}"
SERVER_NAME="${HAPPIER_SERVER_NAME:-default}"
SERVER_URL="${HAPPIER_SERVER_URL:-https://api.happier.dev}"
WEBAPP_URL="${HAPPIER_WEBAPP_URL:-https://app.happier.dev}"

mkdir -p /var/run /var/log/happier "${DEVBOX_HOME}"
chown -R "${DEVBOX_USER}:${DEVBOX_USER}" "${DEVBOX_HOME}" /var/log/happier /workspace /var/lib/docker

dockerd --host=unix:///var/run/docker.sock > /var/log/happier/dockerd.log 2>&1 &
DOCKERD_PID=$!

cleanup() {
  su - "${DEVBOX_USER}" -c "happier daemon stop" >/dev/null 2>&1 || true
  kill "${DOCKERD_PID}" >/dev/null 2>&1 || true
  wait "${DOCKERD_PID}" || true
}

trap cleanup EXIT INT TERM

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

if su - "${DEVBOX_USER}" -c "happier auth status" >/dev/null 2>&1; then
  su - "${DEVBOX_USER}" -c "happier daemon start || true"
else
  echo "Happier is not linked yet. Run 'docker exec -it -u devbox happier-devbox happier auth login' after the container starts."
fi

wait "${DOCKERD_PID}"
```

- [ ] **Step 4: Build the image and verify the tools exist**

Run:

```bash
docker build -f services/data/happier/Dockerfile -t happier-devbox-test .
docker run --rm happier-devbox-test bash -lc "happier --version && docker --version && git --version && bun --version && node --version && python3 --version && uv --version && go version"
```

Expected: every command prints a version and exits `0`.

- [ ] **Step 5: Commit the image and script scaffolding**

Run:

```bash
git add services/data/happier/Dockerfile services/data/happier/bootstrap-ssh.sh services/data/happier/healthcheck.sh services/data/happier/entrypoint.sh
git commit -m "feat: add happier devbox image"
```

Expected: commit succeeds.

## Task 3: Document Local Configuration and First-Run Flow

**Files:**
- Create: `docs/happier-devbox.md`

- [ ] **Step 1: Write the local environment contract**

Create `docs/happier-devbox.md` with the env keys the user must add to the repo-local `.env`:

````markdown
# Happier Devbox

## Required `.env` entries

Add these values to the root `.env` on the Docker host:

```dotenv
HAPPIER_SERVER_NAME=default
HAPPIER_SERVER_URL=https://api.happier.dev
HAPPIER_WEBAPP_URL=https://app.happier.dev
HAPPIER_SSH_KEY_PATH=/absolute/path/to/id_ed25519
HAPPIER_SSH_PUBLIC_KEY_PATH=/absolute/path/to/id_ed25519.pub
HAPPIER_SSH_KNOWN_HOSTS_PATH=/absolute/path/to/known_hosts
```
````

- [ ] **Step 2: Document first boot, linking, and GitHub verification**

Append the startup and auth workflow:

````markdown
## First start

```bash
docker compose up -d --build happier-devbox
docker compose logs -f happier-devbox
```

If the container prints that Happier is not linked yet, authenticate from the host:

```bash
docker exec -it -u devbox happier-devbox bash
happier auth login
happier daemon start
happier daemon status
exit
```

Verify GitHub SSH access:

```bash
docker exec -it -u devbox happier-devbox ssh -T git@github.com
docker exec -it -u devbox happier-devbox git clone git@github.com:OWNER/REPO.git /workspace/REPO
```
````

- [ ] **Step 3: Document nested Docker usage and cleanup**

Append the runtime verification and cleanup commands:

````markdown
## Nested Docker smoke test

```bash
docker exec -it -u devbox happier-devbox docker run --rm hello-world
```

## Restart persistence check

```bash
docker compose restart happier-devbox
docker exec -it happier-devbox bash -lc "test -d /workspace/REPO/.git && docker image ls"
```

## Cleanup

Prune nested Docker state without touching the host daemon:

```bash
docker exec -it happier-devbox docker system prune -af --volumes
```

Remove only the nested Docker storage volume:

```bash
docker compose down
docker volume rm "$(docker volume ls --format '{{.Name}}' | rg '_happier-docker-data$')"
```
````

- [ ] **Step 4: Verify the doc is executable**

Run:

```bash
rg -n "HAPPIER_SSH_KEY_PATH|happier auth login|docker run --rm hello-world|docker system prune" docs/happier-devbox.md
```

Expected:

```text
HAPPIER_SSH_KEY_PATH
happier auth login
docker run --rm hello-world
docker system prune
```

- [ ] **Step 5: Commit the operator docs**

Run:

```bash
git add docs/happier-devbox.md
git commit -m "docs: add happier devbox operations guide"
```

Expected: commit succeeds.

## Task 4: Bring Up the Devbox and Verify Persistence

**Files:**
- Test: runtime verification only

- [ ] **Step 1: Start the service and confirm health**

Run:

```bash
docker compose up -d --build happier-devbox
docker compose ps happier-devbox
docker inspect --format '{{json .State.Health}}' happier-devbox
```

Expected:

```text
happier-devbox   running
"Status":"healthy"
```

- [ ] **Step 2: Link Happier Cloud and verify daemon status**

Run:

```bash
docker exec -it -u devbox happier-devbox bash
happier auth login
happier daemon start
happier daemon status
exit
```

Expected:

```text
Daemon: running
Server: https://api.happier.dev
```

- [ ] **Step 3: Clone a private repository into the persistent workspace**

Run:

```bash
docker exec -it -u devbox happier-devbox bash -lc "ssh -T git@github.com || true"
docker exec -it -u devbox happier-devbox git clone git@github.com:OWNER/PRIVATE_REPO.git /workspace/PRIVATE_REPO
docker exec -it -u devbox happier-devbox test -d /workspace/PRIVATE_REPO/.git
```

Expected: the clone succeeds and the `.git` directory exists.

- [ ] **Step 4: Verify nested Docker isolation**

Run:

```bash
docker exec -it -u devbox happier-devbox docker run --rm hello-world
docker ps --format '{{.Names}}' | rg '^happier-devbox$'
docker ps --format '{{.Names}}' | rg 'hello-world' && exit 1 || true
```

Expected:

```text
Hello from Docker!
happier-devbox
```

The host daemon should not retain a `hello-world` container because the nested daemon handled it.

- [ ] **Step 5: Verify restart persistence**

Run:

```bash
docker exec -it -u devbox happier-devbox bash -lc "echo persistence-check > /workspace/.persistence-check && docker pull hello-world"
docker compose restart happier-devbox
docker exec -it -u devbox happier-devbox bash -lc "test -f /workspace/.persistence-check && docker image inspect hello-world >/dev/null"
```

Expected: both checks exit `0`.

- [ ] **Step 6: Commit the validated implementation**

Run:

```bash
git status --short
git commit --allow-empty -m "test: validate happier devbox runtime"
```

Expected: the working tree is clean before the empty verification commit is created.
