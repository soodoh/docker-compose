#!/bin/sh

LOG_PREFIX="[MAM]"
MAM_URL="https://t.myanonamouse.net/json/dynamicSeedbox.php"
CURRENT_IP=$(cat /tmp/gluetun/ip 2> /dev/null)
RESPONSE_FILE=/tmp/MAM.output
# Should persist between container restarts
COOKIE_FILE=/gluetun/MAM.cookies

echo "$LOG_PREFIX Executing seedbox IP script..."

# Early exit conditions
if [ -z "$CURRENT_IP" ]; then
  echo "$LOG_PREFIX Current IP has not yet been set!"
  exit 1
fi

# On first run, we need to create a new MAM_ID from myanonamouse's Security section
# And execute via `docker exec -it gluetun ash` & `MAM_ID=... sh /scripts/update_mam_ip.sh`
if [ -n "$MAM_ID" ]; then
  echo "$LOG_PREFIX MAM_ID environment detected... Creating a new session with this."
  echo -e ".t.myanonamouse.net\tTRUE\t/\tFALSE\t0\tmam_id\t$MAM_ID" > "$COOKIE_FILE"
fi

grep mam_id ${COOKIE_FILE} > /dev/null 2>/dev/null
if [ $? -ne 0 ]; then
  echo "$LOG_PREFIX No cookie file found, please reinitialize with a new MAM_ID"
  exit 1
fi

echo "$LOG_PREFIX Initiating request..."
# Unlike curl, wget only saves cookies on successful HTTP requests
wget \
  --load-cookies="$COOKIE_FILE" \
  --save-cookies="$COOKIE_FILE" \
  --keep-session-cookies \
  -O "$RESPONSE_FILE" \
  "$MAM_URL" > /dev/null
echo "$LOG_PREFIX Received response: `cat $RESPONSE_FILE`"

grep '"Success":true' $RESPONSE_FILE > /dev/null 2>/dev/null
if [ $? -ne 0 ]; then
  echo "$LOG_PREFIX Request failed! You may need to reinitialize the session with a new MAM_ID"
  exit 1
fi

# grep -E 'No Session Cookie|Invalid session' $RESPONSE_FILE > /dev/null 2>/dev/null
# if [ $? -eq 0 ]; then
#   echo "Response: `cat $RESPONSE_FILE`"
#   echo "Current cookie file is invalid.  Please delete it, set the mam_id, and restart the container."
#   exit 1
# fi
# grep "Last change too recent" $RESPONSE_FILE > /dev/null 2>/dev/null
# if [ $? -eq 0 ]; then
#   echo "Last update too recent - sleeping"
# fi

echo "$LOG_PREFIX Request was successful!"
exit 0
