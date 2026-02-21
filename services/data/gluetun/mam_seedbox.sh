#!/bin/sh

LOG_PREFIX="[MAM]"
MAM_URL="https://t.myanonamouse.net/json/dynamicSeedbox.php"
CURRENT_IP=$(cat /tmp/gluetun/ip 2>/dev/null)
RESPONSE_FILE=/tmp/MAM.output
RETRY_DURATION_MINS=10
# Should persist between container restarts
COOKIE_FILE=/gluetun/MAM.cookies
TEMP_COOKIE_FILE=/tmp/MAM.cookies

echo "$LOG_PREFIX Executing seedbox IP script..."

# Install curl, since running in Gluetun's default Alpine container
if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found! Installing..."
  # Gluetun container uses Alpine linux, so apk is used here
  apk update
  apk add curl
fi

# Early exit conditions
if [ -z "$CURRENT_IP" ]; then
  echo "$LOG_PREFIX Current IP has not yet been set!"
  exit 1
fi

make_request() {
  grep mam_id "$COOKIE_FILE" >/dev/null 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "$LOG_PREFIX No cookie file found, please reinitialize with a new MAM_ID"
    exit 1
  fi

  echo "$LOG_PREFIX Initiating request..."
  curl -s -b "$COOKIE_FILE" -c "$TEMP_COOKIE_FILE" "$MAM_URL" >$RESPONSE_FILE

  # Unlike curl, wget only saves cookies on successful HTTP requests
  # wget \
  #   --load-cookies="$COOKIE_FILE" \
  #   --save-cookies="$COOKIE_FILE" \
  #   --keep-session-cookies \
  #   -O "$RESPONSE_FILE" \
  #   "$MAM_URL"
  echo "$LOG_PREFIX Received response: $(cat "$RESPONSE_FILE")"
}

# On first run, we need to create a new MAM_ID from myanonamouse's Security section
# And execute via `docker exec -it gluetun ash` & `MAM_ID=... sh /scripts/update_mam_ip.sh`
if [ -n "$MAM_ID" ]; then
  echo "$LOG_PREFIX MAM_ID environment detected... Creating a new session with this."
  printf ".myanonamouse.net\tTRUE\t/\tTRUE\t0\tmam_id\t%s" "$MAM_ID" >"$COOKIE_FILE"
fi

make_request

grep 'Last change too recent' $RESPONSE_FILE >/dev/null 3>/dev/null
if [ $? -eq 0 ]; then
  echo "$LOG_PREFIX Last change too recent, retrying in $RETRY_DURATION_MINS minutes..."
  sleep $((RETRY_DURATION_MINS * 60))
  make_request
fi

grep '"Success":true' $RESPONSE_FILE >/dev/null 2>/dev/null
if [ $? -ne 0 ]; then
  echo "$LOG_PREFIX Request failed! You may need to reinitialize the session with a new MAM_ID"
  exit 1
fi

mv "$TEMP_COOKIE_FILE" "$COOKIE_FILE"
echo "$LOG_PREFIX Request was successful!"
exit 0
