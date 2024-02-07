#!/bin/bash

docker stop portainer
docker rm portainer

docker run -d \
  --restart always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v portainer_data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e "TZ=America/Los_Angeles" \
  --name portainer \
  portainer/portainer-ce:latest
