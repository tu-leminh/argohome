#!/bin/sh
echo "Fixing permissions on /data..."

# Shared media directories (all media apps use UID 1000)
chown -R 1000:1000 /data/shared

# Config directories: chown each subdirectory individually,
# skipping dirs owned by other UIDs (e.g. postgres runs as UID 26)
SKIP="nextcloud-db nextcloud-app"
for dir in /data/configs/*/; do
  name=$(basename "$dir")
  case " $SKIP " in
    *" $name "*) echo "Skipping $dir (excluded)" ;;
    *) chown -R 1000:1000 "$dir" ;;
  esac
done

# Secure Traefik ACME files (must be 600)
TRAEFIK_DATA_PATH="/data/configs/traefik"
echo "Securing ACME storage at ${TRAEFIK_DATA_PATH}..."
if ls ${TRAEFIK_DATA_PATH}/*.json 1> /dev/null 2>&1; then
  chown 1000:1000 ${TRAEFIK_DATA_PATH}/*.json
  chmod 600 ${TRAEFIK_DATA_PATH}/*.json
fi

echo "Done."
