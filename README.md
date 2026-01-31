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
*   **Argo CD:** `https://argo.epricesx.duckdns.org`
*   **Traefik Dashboard:** `https://192.168.1.111/dashboard/`

#### Cloud & Productivity
*   **Nextcloud:** `https://nextcloud.epricesx.duckdns.org`
    *   *Database Host:* `postgresql.infra.svc.cluster.local`
    *   *Database User:* `postgres`
    *   *Database Pass:* `nextcloudpassword`

#### Media Stack
*   **Sonarr:** `https://sonarr.epricesx.duckdns.org` (Local: `http://192.168.1.150:8989`)
*   **Radarr:** `https://radarr.epricesx.duckdns.org` (Local: `http://192.168.1.151:7878`)
*   **Prowlarr:** `https://prowlarr.epricesx.duckdns.org` (Local: `http://192.168.1.152:9696`)
*   **qBittorrent:** `https://qbittorrent.epricesx.duckdns.org` (Local: `http://192.168.1.153:8080`)
*   **Jellyfin:** `https://jellyfin.epricesx.duckdns.org` (Local: `http://192.168.1.154:8096`)

## Architecture Highlights

*   **GitOps:** Argo CD manages all applications via an "App of Apps" pattern (`bootstrap/applicationset.yaml`).
*   **Networking:** MetalLB provides Layer 2 LoadBalancing; Traefik handles Ingress and SSL.
*   **Storage:** All data resides in `/data/apps/` on the host, mounted via HostPath PVs.
*   **Database:** A shared PostgreSQL instance handles backend storage for apps like Nextcloud, configured for robust reconnection after cluster resets.

## Management

To deploy a new application, simply commit a Helm chart to the `apps/` directory. Argo CD will automatically discover and deploy it to the cluster.
