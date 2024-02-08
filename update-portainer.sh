#!/bin/bash

# Check if the container named "portainer" is running
if [ "$(docker inspect -f '{{.State.Running}}' portainer 2>/dev/null)" == "true" ]; then
    echo "Stopping container named 'portainer'..."
    docker stop portainer
fi
# Check if the container with the name "portainer" exists
if [ "$(docker ps -aq -f name=portainer)" ]; then
    echo "Removing container named 'portainer'..."
    docker rm portainer
fi
# Check if the volume named "portainer_data" exists
if ! docker volume inspect portainer_data &> /dev/null; then
    echo "Creating volume named 'portainer_data'..."
    docker volume create portainer_data
else
    echo "Volume named 'portainer_data' already exists."
fi
# Check if the network named "proxy" exists
if ! docker network inspect proxy &> /dev/null; then
    echo "Creating network named 'proxy'..."
    docker network create proxy
else
    echo "Network named 'proxy' already exists."
fi

docker run -d \
  --restart always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v portainer_data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -network=proxy
  -e "TZ=America/Los_Angeles" \
  --name portainer \
  portainer/portainer-ce:latest
