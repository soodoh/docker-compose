#!/bin/bash

docker compose --env-file .env \
  -f ./apps-compose.yml \
  -f ./hass-compose.yml \
  -f ./nextcloud-compose.yml \
  -f ./downloaders-compose.yml \
  -f ./auth-compose.yml \
  -f ./infra-compose.yml \
  "$@"
