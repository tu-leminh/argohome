#!/bin/bash
set -e
set -x # Enable debug output

# --- Configuration ---
REPO_URL="https://github.com/tu-leminh/argohome"
GIT_USER="tu-leminh"
GIT_TOKEN="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"

echo "🚀 Starting GitOps Bootstrap..."

# --- 1. MicroK8s Reset & Install ---
if command -v microk8s &>/dev/null; then
  echo "♻️  Purging existing MicroK8s..."
  sudo snap remove microk8s --purge
fi

echo "📦 Installing MicroK8s..."
sudo snap install microk8s --classic

# Setup Groups & Storage
sudo usermod -a -G microk8s $USER
[ -n "$SUDO_USER" ] && sudo usermod -a -G microk8s "$SUDO_USER"
sudo mkdir -p /data/sonarr/config /data/media/{tv,downloads}
sudo chmod -R 777 /data

# --- 2. Cluster Setup ---
echo "⏳ Waiting for Cluster..."
sudo microk8s status --wait-ready
sudo microk8s enable helm3
sudo microk8s enable dns
sudo microk8s enable hostpath-storage

# Export kubeconfig (for root)
mkdir -p ~/.kube
sudo microk8s config >~/.kube/config
chmod 600 ~/.kube/config
sleep 180

# Export kubeconfig (for sudo user, if exists)
if [ -n "$SUDO_USER" ]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  mkdir -p "$USER_HOME/.kube"
  sudo microk8s config >"$USER_HOME/.kube/config"
  chown -R "$SUDO_USER" "$USER_HOME/.kube"
  chmod 600 "$USER_HOME/.kube/config"
fi

# --- 3. Install Argo CD ---
echo "🐙 Installing Argo CD..."
sudo microk8s helm3 repo add argo https://argoproj.github.io/argo-helm
sudo microk8s helm3 repo update >/dev/null
sudo microk8s helm3 upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=LoadBalancer \
  --set server.insecure=true

# --- 4. Configure Credentials ---
echo "🔐 Registering Private Repository..."
cat <<EOF | sudo microk8s kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $REPO_URL
  username: $GIT_USER
  password: $GIT_TOKEN
EOF

# --- 5. Deploy Apps ---
echo "🚀 Applying ApplicationSet..."
sudo microk8s kubectl apply -f bootstrap/applicationset.yaml

echo "==========================================================="
echo "🎉 Bootstrap Complete!"
echo -n "🔑 Admin Password: "
sudo microk8s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo ""
echo "==========================================================="
