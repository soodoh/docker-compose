#!/bin/bash

docker compose --env-file .env \
  -f ./compose/apps.yml \
  -f ./compose/hass.yml \
  -f ./compose/nextcloud.yml \
  -f ./compose/downloaders.yml \
  -f ./compose/auth.yml \
  -f ./compose/infra.yml \
  "$@"
