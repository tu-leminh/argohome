#!/bin/sh
echo "Fixing permissions on /data..."
# Set ownership to User 1000 (Host/Media/Traefik standard)
chown -R 1000:1000 /data

# Secure Traefik ACME files (Must be 600)
TRAEFIK_DATA_PATH="/data/configs/traefik"
echo "Securing ACME storage at ${TRAEFIK_DATA_PATH}..."
if ls ${TRAEFIK_DATA_PATH}/*.json 1> /dev/null 2>&1; then
  # Ensure owner is 1000 (redundant but safe)
  chown 1000:1000 ${TRAEFIK_DATA_PATH}/*.json
  # Strictly restrict to owner-only
  chmod 600 ${TRAEFIK_DATA_PATH}/*.json
fi

echo "Done."
