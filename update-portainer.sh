#!/bin/bash

docker stop portainer

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

# Check if the network named "proxy" exists
if ! docker network inspect arr_network &> /dev/null; then
    echo "Creating network named 'arr_network'..."
    docker network create arr_network
else
    echo "Network named 'arr_network' already exists."
fi

docker run -d \
  --restart always \
  -p 8000:8000 \
  -p 9443:9443 \
  -v portainer_data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e "TZ=America/Los_Angeles" \
  --network=proxy \
  --name portainer \
  portainer/portainer-ce:latest

echo "Done!"
