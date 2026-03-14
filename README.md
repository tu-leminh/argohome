# GitOps Home Lab

A robust, self-healing Home Lab powered by **MicroK8s** and **Argo CD**.

## Overview

This project defines my entire home server infrastructure as code (IoC). It is designed to be **stateless** at the compute layer, meaning the entire Kubernetes cluster can be destroyed and recreated without losing application data, which is safely persisted on the host filesystem.

## Quick Start

### 1. Bootstrap Cluster
Initialize the cluster and Argo CD:
```bash
./bootstrap.sh
```

### 2. Access Applications
*   **Homepage Dashboard:** `https://epricesx.duckdns.org` (or configured DDNS)
    *   Central hub for all services.
*   **Argo CD:** `https://argo.epricesx.duckdns.org`
    *   **Credentials:** Admin user, password stored in `argocd-initial-admin-secret` (or configured via SSO).

### 3. Application Access
Services are exposed via three methods:
1.  **Local Network (MetalLB):** Direct IP access (e.g., `192.168.1.150` for Sonarr).
2.  **External (Traefik + DDNS):** `https://<app>.epricesx.duckdns.org`.
3.  **Private Mesh (Tailscale):** `https://<app>.platy-python.ts.net` (Secure remote access without open ports).

#### Core Services
*   **Argo CD:** GitOps Controller.
*   **Homepage:** Beautiful start page.

#### Cloud & Productivity

#### Media Stack (The *Arr* Suite)
*   **Sonarr:** TV Series management.
*   **Radarr:** Movie management.
*   **Prowlarr:** Indexer manager (connects Sonarr/Radarr to trackers).
*   **Transmission:** BitTorrent client.
*   **Deluge:** BitTorrent client.
*   **Jellyfin:** Media server/player.

## Architecture Highlights

*   **GitOps:** Argo CD manages all applications via an "App of Apps" pattern (`bootstrap/applicationset.yaml`).
*   **Networking:**
    *   **MetalLB:** Layer 2 LoadBalancing (IP Pool: `192.168.1.100-200`).
    *   **Traefik:** Ingress Controller handling SSL (Let's Encrypt) and routing.
    *   **Tailscale:** Kubernetes Operator for secure, VPN-less remote access to internal services.
*   **Storage:** All persistent data resides in `/data/apps/` on the host (`dell`), mounted via HostPath PVs.

## Management

To deploy a new application:
1.  Create a Helm chart in `apps/<category>/<name>`.
2.  Commit and push to the repo.
3.  Argo CD's `ApplicationSet` will automatically discover and deploy it.

## Troubleshooting

*   **Argo CD Sync Stuck:** Check resource limits on `repo-server` or large CRD issues (Server-Side Apply is enabled).
*   **Access Issues:** Verify IngressRoutes for Traefik or `Ingress` resources for Tailscale (ensure ports match service target ports).