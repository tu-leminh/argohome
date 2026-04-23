#!/bin/sh
set -e
# Install dependencies
apk add --no-cache bash curl jq coreutils

# Use bash for the main logic to support pipefail and other bashisms
/bin/bash <<'INNER_EOF'
set -euf -o pipefail

if [ -z "$TAILNET" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
  echo "Error: TAILNET, client_id, and client_secret environment variables must be set."
  exit 1
fi

echo "Authenticating..."
TOKEN_RESPONSE=$(curl -s -d "client_id=$client_id" -d "client_secret=$client_secret" -d "grant_type=client_credentials" "https://api.tailscale.com/api/v2/oauth/token")
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r .access_token)

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: Could not obtain access token."
  exit 1
fi

CUTOFF_DATE=$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)
echo "Fetching devices for tailnet: $TAILNET"
echo "Removing devices last seen before: $CUTOFF_DATE"

DEVICES=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://api.tailscale.com/api/v2/tailnet/$TAILNET/devices")

# Iterate and delete
echo "$DEVICES" | jq -r --arg CUTOFF_DATE "$CUTOFF_DATE" '.devices[] | select(.lastSeen < $CUTOFF_DATE) | .id' | while read -r DEVICE_ID; do
  echo "Removing device ${DEVICE_ID}"
  curl -s -X DELETE -H "Authorization: Bearer $ACCESS_TOKEN" "https://api.tailscale.com/api/v2/device/${DEVICE_ID}"
done
echo "Cleanup complete."
INNER_EOF
