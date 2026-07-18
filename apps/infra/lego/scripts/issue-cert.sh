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

if [ -s "$CERT_DIR/${LEGO_CERT_FILE_STEM}.crt" ]; then
  echo "Existing cert found for ${LEGO_CERT_FILE_STEM}, renewing"
  lego --accept-tos --email "$LEGO_EMAIL" --dns "$LEGO_PROVIDER" --path "$STORAGE" "$@" renew --days 30
else
  echo "No existing cert for ${LEGO_CERT_FILE_STEM}, issuing"
  lego --accept-tos --email "$LEGO_EMAIL" --dns "$LEGO_PROVIDER" --path "$STORAGE" "$@" run
fi

echo "Writing Secret ${SECRET_NAME} in namespace ${NAMESPACE}"
kubectl create secret tls "$SECRET_NAME" -n "$NAMESPACE" \
  --cert="$CERT_DIR/${LEGO_CERT_FILE_STEM}.crt" \
  --key="$CERT_DIR/${LEGO_CERT_FILE_STEM}.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done"
