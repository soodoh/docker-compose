#!/bin/bash

BACKUP_FILENAME="backup-2024-04-14T00-00-00.tar.gz"

docker stop $(docker ps -q)

docker run --rm -it \
  -v data:/backup/my-app-backup \
  -v media_audiobookshelf-config:/backup/audiobookshelf-config \
  -v media_audiobookshelf-metadata:/backup/audiobookshelf-metadata \
  -v media_calibre-config:/backup/calibre-config \
  -v media_calibre-plugins:/backup/calibre-plugins \
  -v media_calibre-web:/backup/calibre-web \
  -v media_flood-open:/backup/flood-open \
  -v media_flood-vpn:/backup/flood-vpn \
  -v media_gluetun:/backup/gluetun \
  -v media_jellyfin-cache:/backup/jellyfin-cache \
  -v media_jellyfin-config:/backup/jellyfin-config \
  -v media_jellyseerr:/backup/jellyseerr \
  -v media_lidarr:/backup/lidarr \
  -v media_prowlarr:/backup/prowlarr \
  -v media_radarr:/backup/radarr \
  -v media_radarr-4k:/backup/radarr-4k \
  -v media_readarr:/backup/readarr \
  -v media_sonarr:/backup/sonarr \
  -v media_sonarr-4k:/backup/sonarr-4k \
  -v media_speakarr:/backup/speakarr \
  -v media_tachidesk:/backup/tachidesk \
  -v media_tachidesk-gluetun:/backup/tachidesk-gluetun \
  -v media_transmission-open:/backup/transmission-open \
  -v media_transmission-vpn:/backup/transmission-vpn \
  -v network_authelia:/backup/authelia \
  -v network_caddy:/backup/caddy \
  -v network_omada-data:/backup/omada-data \
  -v network_omada-logs:/backup/omada-logs \
  -v network_pihole:/backup/pihole \
  -v network_pihole-dnsmasq:/backup/pihole-dnsmasq \
  -v /mnt/media/backups:/archive:ro \
    alpine tar -xvzf /archive/$BACKUP_FILENAME
