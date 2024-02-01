# Portainer Compose Repo

Used for my personal home server. My home server is running a Docker instance of Portainer, which polls this repo for various compose.yml files and will re-deploy them to match this repo's "main" branch.

## Media compose.yml

Expected environment variables to be set:

```
TZ=America/Los_Angeles
SONARR_API_KEY=
RADARR_API_KEY=
TORRENT_USERNAME=
TORRENT_PASSWORD=
VPN_PROVIDER=
VPN_USERNAME=
VPN_PASSWORD=
PLEX_CLAIM=
```

## Network compose.yml

Expected environment variables to be set:

```
TZ=America/Los_Angeles
```

## Portainer compose.yml

Portainer cannot update itself. Just keeping this file here to easly re-run & update Portainer itself when needed.
