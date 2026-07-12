#!/bin/sh
echo "Fixing permissions on /data..."

# Shared media directories (all media apps use UID 1000)
chown -R 1000:1000 /data/tier3/shared

# Config directories: all apps run as UID 1000
chown -R 1000:1000 /data/tier2/configs

# Secure Traefik ACME files (must be 600)
TRAEFIK_DATA_PATH="/data/tier2/configs/traefik"
echo "Securing ACME storage at ${TRAEFIK_DATA_PATH}..."
if ls ${TRAEFIK_DATA_PATH}/*.json 1> /dev/null 2>&1; then
  chown 1000:1000 ${TRAEFIK_DATA_PATH}/*.json
  chmod 600 ${TRAEFIK_DATA_PATH}/*.json
fi

echo "Done."
