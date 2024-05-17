#!/bin/bash
 
echo "Executing port forwarding script..."

PREVIOUS_PORT=$(cat /tmp/gluetun/previous_port 2>/dev/null || echo "EMPTY")
FORWARDED_PORT=$(cat /tmp/gluetun/forwarded_port 2> /dev/null)

# Install dependencies if needed
# (I don't want to rebuild a docker image just for this)
if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found! Installing..."
  # Gluetun container uses Alpine linux, so apk is used here
  apk update
  apk add curl
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found! Installing..."
  apk update
  apk add jq
fi

# Early exit conditions
if [ -z "$FORWARDED_PORT" ]; then
  echo "Current port has not yet been set!"
  exit 0
fi
if [ -f /tmp/gluetun/previous_port ] && [ "$PREVIOUS_PORT" = "$FORWARDED_PORT" ]; then
  echo "Previous port & Current port already are matching: $FORWARDED_PORT"
  exit 0
fi

echo "Initiating request..."
RESPONSE=$(curl -i -X POST -d "json={\"listen_port\": $FORWARDED_PORT}" "http://127.0.0.1:8080/api/v2/app/setPreferences")
echo "$RESPONSE"
# Log whether success or fail
echo "Updated qbittorrent port to $FORWARDED_PORT"
cp /tmp/gluetun/forwarded_port /tmp/gluetun/previous_port
