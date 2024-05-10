#!/bin/bash
 
echo "Executing seedbox IP script..."

PREVIOUS_IP=$(cat /tmp/gluetun/previous_ip 2>/dev/null || echo "EMPTY")
IP=$(cat /tmp/gluetun/ip 2> /dev/null)
RATE_LIMIT=30 # (in minutes)
LAST_TIMESTAMP=$(cat /tmp/gluetun/last_timestamp 2>/dev/null || echo 0)
MINS_ELAPSED=$(( ( $(date +%s) - LAST_TIMESTAMP ) / 60 ))

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
if [ -z "$MAM_ID" ] || [ -z "$MAM_URL" ]; then
  echo "Required environment variables are missing!"
  echo "MAM_ID: $MAM_ID"
  echo "MAM_URL: $MAM_URL"
  exit 1
fi
if [ -z "$IP" ]; then
  echo "Current IP has not yet been set!"
  exit 0
fi
if [ -f /tmp/gluetun/previous_ip ] && [ "$PREVIOUS_IP" = "$IP" ]; then
  echo "Previous IP & Current IP already are matching: $IP"
  exit 0
fi
if [ -f /tmp/gluetun/last_timestamp ] && [ "$MINS_ELAPSED" -lt "$RATE_LIMIT" ]; then
  echo "Exceeded rate limit: $RATE_LIMIT minutes!"
  echo "Last called API $MINS_ELAPSED minutes ago."
  exit 0
fi

echo "Initiating request..."
RESPONSE=$(curl -s -b "mam_id=$MAM_ID" "$MAM_URL")
# Log whether success or fail
date +%s > /tmp/gluetun/last_timestamp
echo "Request completed at $(date "+%Y-%m-%d %H:%M:%S")"

SUCCESS="$(echo "$RESPONSE" | jq ".Success")"
MESSAGE="$(echo "$RESPONSE" | jq ".msg")"
if [ "$SUCCESS" = "true" ]; then
  echo "Request was successful! $MESSAGE"
  cp /tmp/gluetun/ip /tmp/gluetun/previous_ip
  echo "Saved current IP: $(cat /tmp/gluetun/ip)"
else
  echo "Request failed! $MESSAGE"
  echo "$RESPONSE"
fi
