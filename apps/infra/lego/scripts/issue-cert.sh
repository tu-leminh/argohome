#!/bin/sh
set -eu

apk add --no-cache curl tar ca-certificates >/dev/null

echo "Installing kubectl ${KUBECTL_VERSION}"
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

echo "Installing lego ${LEGO_VERSION}"
curl -fsSL "https://github.com/go-acme/lego/releases/download/${LEGO_VERSION}/lego_${LEGO_VERSION}_linux_amd64.tar.gz" \
  | tar xz -C /usr/local/bin lego
chmod +x /usr/local/bin/lego

STORAGE=/lego-storage
CERT_DIR="$STORAGE/certificates"
mkdir -p "$STORAGE"

set --
for d in $LEGO_DOMAINS; do
  set -- "$@" -d "$d"
done

# lego v5 merged "renew" into "run" - it renews in place when a cert already
# exists in --path and is due, and issues fresh otherwise. All ACME flags are
# now subcommand flags of "run", not global ones.
lego run --accept-tos --email "$LEGO_EMAIL" --dns "$LEGO_PROVIDER" --path "$STORAGE" "$@"

echo "Writing Secret ${SECRET_NAME} in namespace ${NAMESPACE}"
kubectl create secret tls "$SECRET_NAME" -n "$NAMESPACE" \
  --cert="$CERT_DIR/${LEGO_CERT_FILE_STEM}.crt" \
  --key="$CERT_DIR/${LEGO_CERT_FILE_STEM}.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done"
