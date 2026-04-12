# Repository Guidelines

## Project Structure & Module Organization
This repository is a Docker Compose monorepo for a home server. The root [`docker-compose.yml`](./docker-compose.yml) is the entrypoint and merges the stack files in `services/*.yml` via Compose `include`. Each file groups related services, for example `services/infra.yml`, `services/servarr.yml`, and `services/hass.yml`. Runtime config and helper assets live under `services/data/`, including the shared [`services/data/Caddyfile`](./services/data/Caddyfile) and Gluetun hook scripts in `services/data/gluetun/`.

## Build, Test, and Development Commands
Use Docker Compose from the repo root so `.env` is loaded automatically.

- `docker compose config` validates and renders the merged configuration.
- `docker compose up -d` starts every stack.
- `docker compose up -d jellyfin` starts or updates a single service.
- `docker compose logs -f caddy` tails logs for one service.
- `docker compose pull` refreshes container images before deployment.
- `bunx commitlint --edit .git/COMMIT_EDITMSG` checks a commit message manually.

## Coding Style & Naming Conventions
Compose files use two-space YAML indentation. Keep services grouped by domain in the existing `services/*.yml` files instead of creating one file per container. Reuse YAML anchors for shared settings such as logging and backup env blocks when possible. Prefer lowercase, hyphenated names for files, service IDs, container names, volumes, and networks. Keep helper scripts in `services/data/` executable and narrowly scoped.

## Testing & Validation Guidelines
There is no automated unit test suite here; validation is configuration-focused. Run `docker compose config` after every change and start the affected service with `docker compose up -d <service>` when practical. For routing or VPN-related edits, inspect logs with `docker compose logs -f <service>` to confirm the container boots cleanly and expected ports or hooks are applied.

## Commit & Pull Request Guidelines
Commits follow Conventional Commits, for example `feat: add vikunja` or `fix: remove env var`. `lefthook` runs `commitlint` on `commit-msg`, so keep commit subjects short and formatted correctly. Pull requests should describe the operational impact, list changed services or networks, note any required `.env` additions, and include relevant log snippets or screenshots when a UI or reverse-proxy route changes.

## Security & Configuration Tips
Do not commit secrets from `.env`, `.authentik.env`, or `.openfit.env`. Treat image tag bumps, port changes, and network edits as production changes: review exposed ports, VPN routing, backup labels, and persistent volume mappings before merging.
