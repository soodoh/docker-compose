# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Docker Compose configuration for a personal home server running on Proxmox LXC. Services are split across multiple compose files organized by function, all merged together through `docker-compose.yml` using Compose `include`.

## Commands

```bash
# Run any docker compose command across all stacks
docker compose <docker-compose-args>

# Examples:
docker compose up -d                # Start all services
docker compose up -d jellyfin       # Start a single service
docker compose logs -f caddy        # Tail logs for a service
docker compose pull                 # Pull latest images
```

`docker-compose.yml` includes all `*-compose.yml` files. Docker Compose automatically loads `.env` from the project root.

## Architecture

### Compose Stacks

Each `*-compose.yml` file is a logical group. All are loaded together as one compose project:

- **infra** - Core infrastructure: Caddy (reverse proxy), Pi-hole (DNS), Omada (network controller), DDNS updater, backup jobs (daily local + weekly S3)
- **auth** - Authentik SSO with its own Postgres and Redis
- **apps** - Media/content apps: Jellyfin, Audiobookshelf, Calibre, Calibre-Web-Automated, Karaoke Eternal
- **downloaders** - Arr stack behind Gluetun VPN: Sonarr, Radarr (+ 4K instance), Bookshelf (Readarr fork), Prowlarr, qBittorrent, Recyclarr, Unpackerr, Jellyseerr, Tachidesk (x2), FlareSolverr
- **hass** - Home Assistant (host network), Z-Wave JS UI, Mosquitto MQTT, Frigate NVR (with Coral TPU + AMD GPU)
- **nextcloud** - Nextcloud with MariaDB and Redis
- **openfit** - OpenFit fitness app

### Networking

Services communicate via named Docker networks with fixed subnets:
- `proxy` (172.23.0.0/16) - Services exposed through Caddy
- `authentik` (172.20.0.0/16) - Auth stack internal
- `arr_network` (172.21.0.0/16) - Downloader inter-service
- `infra` (172.22.0.0/16) - Backup jobs
- `hass` - Home automation internal
- `nextcloud` (172.24.0.0/16) - Nextcloud internal

Most downloaders use `network_mode: service:gluetun` to route traffic through VPN. Home Assistant uses `network_mode: host` for mDNS/HomeKit.

### Reverse Proxy

`Caddyfile` defines routing. Most subdomains forward to `authentik-server:9000` for SSO. Specific services (Jellyfin, Audiobookshelf, Calibre-Web, Nextcloud, Karaoke Eternal) get direct reverse proxy entries.

### Environment

All services read from `.env` (loaded automatically by Docker Compose). Authentik uses a separate `.authentik.env`. OpenFit uses `.openfit.env`. Key variables include `$TZ`, `$MEDIA_PATH`, `$BACKUP_PATH`, and various API keys.

### Backups

`docker-volume-backup` runs two schedules via `infra-compose.yml`: daily local (Mon-Sat 6AM, 5-day retention) and weekly remote to S3 (Sun 6AM, 14-day retention). Services labeled `docker-volume-backup.stop-during-backup: true` are stopped during backup.

### VPN Scripts

`scripts/gluetun/` contains post-VPN-connect hooks:
- `gluetun_up.sh` - Entry point, called by Gluetun's `VPN_PORT_FORWARDING_UP_COMMAND`
- `qbittorrent_port.sh` - Updates qBittorrent's listening port to match VPN forwarded port
- `mam_seedbox.sh` - Updates MAM dynamic seedbox IP using cookie-based auth

## Conventions

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (enforced by commitlint + husky)
- Package manager is **Bun** (not npm/pnpm)
- Renovate manages dependency updates (Docker image tags and npm packages)
- YAML anchors (`x-logging`, `x-backup-env`, `x-backup-volumes`) are used for shared config across services
- Volume subpaths are used to consolidate multiple mount points into a single named volume per service
