#!/bin/bash
set -e

# --- Configuration ---
REPO_URL="https://github.com/tu-leminh/argohome"
GIT_USER="tu-leminh"
GIT_TOKEN="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"

echo "🚀 Starting GitOps Bootstrap..."

# --- 1. MicroK8s Reset & Install ---
if command -v microk8s &>/dev/null; then
  echo "♻️  Purging existing MicroK8s..."
  sudo snap remove microk8s --purge >/dev/null
fi

echo "📦 Installing MicroK8s..."
sudo snap install microk8s --classic >/dev/null

# Setup Groups & Storage
sudo usermod -a -G microk8s $USER
[ -n "$SUDO_USER" ] && sudo usermod -a -G microk8s "$SUDO_USER"
sudo mkdir -p /data/sonarr/config /data/media/{tv,downloads}
sudo chmod -R 777 /data

# --- 2. Cluster Setup ---
echo "⏳ Waiting for Cluster..."
sudo microk8s status --wait-ready >/dev/null
echo "🛠️  Enabling addons (helm3, dns, hostpath-storage)..."
sudo microk8s enable helm3 >/dev/null
sudo microk8s enable dns >/dev/null
sudo microk8s enable hostpath-storage >/dev/null

# Export kubeconfig (for root)
mkdir -p ~/.kube
sudo microk8s config >~/.kube/config
chmod 600 ~/.kube/config

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
sudo microk8s helm3 repo add argo https://argoproj.github.io/argo-helm >/dev/null
sudo microk8s helm3 repo update >/dev/null
sudo microk8s helm3 upgrade --install argocd argo/argo-cd \
  --namespace core --create-namespace \
  --set server.service.type=LoadBalancer \
  --set server.insecure=true >/dev/null

# --- 4. Configure Credentials ---
echo "🔐 Registering Private Repository..."
cat <<EOF | sudo microk8s kubectl apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: repo-creds
  namespace: core
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $REPO_URL
  username: $GIT_USER
  password: $GIT_TOKEN
EOF

# --- 4b. Wait for Argo CD ---
echo "⏳ Waiting for Argo CD components to be ready..."
sudo microk8s kubectl wait --for=condition=Available deployment --all -n core --timeout=300s

# --- 5. Deploy Apps ---
echo "🚀 Applying ApplicationSet..."
sudo microk8s kubectl apply -f bootstrap/applicationset.yaml >/dev/null

echo "==========================================================="
echo "🎉 Bootstrap Complete!"
echo "🔑 Admin Password:"
sudo microk8s kubectl -n core get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo ""
echo "==========================================================="
