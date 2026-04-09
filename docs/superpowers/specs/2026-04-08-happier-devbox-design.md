# Happier Devbox Design

## Goal

Add a long-lived Docker-based devbox to this compose repository so Happier clients can connect to it and run sessions against many GitHub projects inside an isolated sandbox. This design is specifically for a single user and does not include self-hosting a Happier server.

## Non-Goals

- Do not self-host any Happier server components.
- Do not expose the devbox publicly through Caddy as part of the initial implementation.
- Do not integrate Authentik, GitHub OAuth, or any other external identity provider for Happier access.
- Do not support multiple users with separate identities or homes.

## Context

This repository is a multi-stack Docker Compose setup for a home server. Existing services are grouped into separate `services/*.yml` files and merged through [`docker-compose.yml`](/Users/pauldiloreto/Projects/docker-compose/docker-compose.yml). Reverse proxying is managed centrally through [`services/data/Caddyfile`](/Users/pauldiloreto/Projects/docker-compose/services/data/Caddyfile), and persistent application state is generally stored in named volumes with backup integration where appropriate.

The Happier docs distinguish between:

- self-hosting a Happier server, which has its own auth policy and provider configuration; and
- connecting clients and terminals to an existing Happier server profile, including Happier Cloud.

For this design, the devbox is only a remote terminal/daemon environment that authenticates to Happier Cloud using Happier's normal device-key flow. Server-side auth policy is out of scope because this repository will not run a Happier server.

## Requirements

- Provide a single long-lived container for one user.
- Persist cloned repos across restarts.
- Persist nested Docker state across restarts.
- Support cloning private GitHub repos over SSH.
- Include common development tooling in the image.
- Allow Happier sessions to run project-specific Docker workloads without touching the host Docker daemon.
- Fit this repository's existing compose organization and operational conventions.

## Recommended Approach

Use one dedicated `happier-devbox` service with embedded Docker-in-Docker. The container owns both the workspace and the nested Docker daemon state. This keeps the mental model simple: one service, one user, one internal workspace, one internal Docker universe.

This is preferred over:

- a host Docker socket mount, which would mix project containers with home-server workloads; and
- a separate Docker sidecar, which is cleaner architecturally but adds extra wiring and operational surface area for the first version.

## Architecture

### Compose Structure

- Add a new compose file at [`services/happier.yml`](/Users/pauldiloreto/Projects/docker-compose/services/happier.yml).
- Add that file to the include list in [`docker-compose.yml`](/Users/pauldiloreto/Projects/docker-compose/docker-compose.yml).
- Build the service from a local Dockerfile, likely under [`services/data/happier/`](/Users/pauldiloreto/Projects/docker-compose/services/data/happier/), to match the repository's existing pattern of colocating service-specific data and helper assets under `services/data`.

### Service Layout

The `happier-devbox` service will:

- run as a long-lived container with `restart: unless-stopped`;
- start an inner Docker daemon inside the container;
- start the Happier CLI/daemon in the same container after Docker is ready;
- expose no public ports by default;
- avoid mounting `/var/run/docker.sock` from the host.

### Persistent Storage

Use separate named volumes for:

- `/workspace` for cloned repositories and repo-local state;
- `/var/lib/docker` for nested Docker images, containers, networks, and volumes;
- the Happier user home/config area for daemon state and any local config that should survive restarts.

This separation allows targeted cleanup. For example, nested Docker state can be reset without deleting repositories.

### SSH Access

Mount SSH material read-only into the container for GitHub access. The initial implementation should assume a single GitHub identity. The design should prefer mounting only the minimum required files, such as:

- a private key;
- a matching public key if needed;
- `known_hosts` or a startup step that initializes GitHub host keys.

The container should not store a GitHub PAT in compose env for this use case.

### Toolchain

The base image should include:

- `git`
- `gh`
- `bun`
- `node`
- `python`
- `uv`
- `go`
- Docker CLI
- common build tooling required by typical repos, such as `build-essential`, `curl`, `ca-certificates`, `openssh-client`, and `make`

The image should pin versions at a practical level for reproducibility, but avoid over-optimizing version management in the first pass.

## Runtime Flow

### Happier Connection Model

The devbox authenticates outbound to Happier Cloud using Happier's normal device-key account model. A one-time link/connect flow is performed from the container using the Happier CLI/daemon, then the daemon remains signed in across restarts via persistent config storage.

No reverse-proxied inbound route is required for the core session workflow because the box is acting as a Happier terminal environment, not as a self-hosted Happier server.

### Session Execution

When a Happier client targets this devbox:

- session commands run inside the `happier-devbox` container;
- repositories live under `/workspace`;
- Git operations use the mounted SSH identity;
- any `docker compose` or `docker run` commands use the inner Docker daemon.

This ensures project containers are isolated from the host daemon that runs the rest of the home-server stacks.

### Restart Behavior

On devbox container restart:

- the outer container restarts;
- the inner Docker daemon restarts from its persisted `/var/lib/docker`;
- existing nested container definitions and images remain available;
- repositories and Happier state remain available.

Nested containers stop when the devbox stops because they are owned by the inner daemon. They become available again when that daemon restarts, subject to their own restart policies and project runtime behavior.

## Networking

The initial service should not be internet-exposed. Two acceptable starting points are:

- attach it to no special reverse-proxy route and rely on outbound connectivity only; or
- attach it to an internal Docker network if needed for egress consistency with the rest of the project.

The design recommendation is to keep it off Caddy initially. If later operational needs justify browser-based access or a web terminal, that can be added in a separate design cycle.

## Logging And Health

Follow repository conventions:

- use the same `json-file` logging settings already used in other compose stacks;
- define a healthcheck that verifies the inner Docker daemon is responding;
- gate startup of the Happier daemon on inner Docker readiness.

If the Happier daemon loses authentication, recovery should be a reconnect/relink flow inside the container without deleting persistent volumes.

## Backup And Retention

Initial backup policy should be conservative:

- include the Happier config/home volume in backups if it contains important daemon linkage state;
- consider whether `/workspace` should be backed up centrally or treated as disposable because the canonical source is GitHub;
- do not automatically back up nested Docker state unless there is a clear recovery need, because it is likely large and mostly reconstructable.

The default recommendation is:

- back up Happier config/home state;
- do not back up `/var/lib/docker`;
- decide separately whether `/workspace` belongs in existing backup jobs based on how much non-committed local state you expect to keep there.

## Error Handling And Cleanup

### Failure Boundaries

Problems inside the devbox should stay local to the devbox volumes:

- repo corruption affects `/workspace`;
- daemon auth issues affect the Happier config volume;
- Docker storage issues affect only the nested Docker data volume.

No failure in the devbox should require touching the host Docker daemon or unrelated home-server services.

### Cleanup Model

Cleanup should be explicit and scoped:

- prune nested images and containers from inside the devbox;
- reset only the nested Docker data volume when Docker state must be discarded;
- delete or rotate the workspace volume only when repo state should be rebuilt from GitHub.

This avoids accidental deletion of host-level services and resources.

## Testing Strategy

The first implementation should verify:

1. the image builds successfully;
2. the container starts and the inner Docker daemon becomes healthy;
3. the Happier daemon can link to the user's Happier Cloud account and retain that state across restart;
4. a private GitHub repository can be cloned over SSH into `/workspace`;
5. a nested Docker workload can be started inside the devbox;
6. nested Docker state and workspace state survive a devbox container restart.

## Open Choices Resolved In This Design

- Single-user only: yes.
- Many repos in one shared workspace: yes.
- Repo source of truth: persistent volume owned by the container.
- GitHub auth for cloning: SSH.
- Project container execution: Docker-in-Docker, not host Docker socket.
- Common language runtimes preinstalled: yes.
- Happier server hosting: no.
- Reverse proxy exposure: not in the initial version.

## Implementation Outline

The follow-up implementation plan should cover:

1. adding the new compose include and compose stack;
2. creating the Dockerfile and entrypoint scripts for inner Docker plus Happier startup;
3. defining persistent volumes and any required env variables;
4. wiring SSH mounts safely;
5. documenting first-run linking and operational commands;
6. verifying startup, Git clone, and nested Docker behavior.
