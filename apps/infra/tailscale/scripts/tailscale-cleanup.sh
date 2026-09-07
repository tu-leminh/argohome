#!/bin/sh
set -eu

: "${TAILNET:?TAILNET is required}"
: "${client_id:?client_id is required}"
: "${client_secret:?client_secret is required}"

apk add --no-cache curl jq >/dev/null

echo "Authenticating to Tailscale API..."
TOKEN=$(curl -sf \
  -d "client_id=$client_id" \
  -d "client_secret=$client_secret" \
  -d "grant_type=client_credentials" \
  https://api.tailscale.com/api/v2/oauth/token | jq -er '.access_token')

echo "Removing proxy devices (tag:k8s) from $TAILNET..."
echo "  (removes matching devices even if still online — operator re-registers them)"
DEVICES=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "https://api.tailscale.com/api/v2/tailnet/$TAILNET/devices" \
)
DEVICE_IDS=$(printf '%s' "$DEVICES" | jq -r '
    .devices[]
    | select((.tags // []) | any(. == "tag:k8s"))
    | select((.tags // []) | all(. != "tag:k8s-operator"))
    | .id
  ')

printf '%s\n' "$DEVICE_IDS" | while read -r id; do
  [ -n "$id" ] || continue
  echo "  removing $id"
  curl -sf -X DELETE -H "Authorization: Bearer $TOKEN" \
    "https://api.tailscale.com/api/v2/device/$id" \
    || echo "  warning: failed to remove $id, continuing"
done
echo "Cleanup complete."
