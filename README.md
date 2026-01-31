# GitOps Home Lab

This repository contains the GitOps configuration for a MicroK8s-based Home Lab, managed by Argo CD.

## Architecture

*   **Cluster:** MicroK8s (Single Node)
*   **GitOps:** Argo CD (App of Apps via ApplicationSet)
*   **Ingress:** Traefik + MetalLB (VIP: `192.168.1.111`)
*   **Storage:** Local HostPath with Node Affinity
*   **DNS:** DuckDNS, FreeMyIP, MyAddr

## Directory Structure

*   `bootstrap/`: Argo CD ApplicationSet.
*   `apps/`: Helm charts organized by category.
    *   `core/`: System apps (Argo CD).
    *   `infra/`: Infrastructure (Traefik, MetalLB, Secrets, CronJobs, Storage).
    *   `media/`: Media apps (Sonarr, Radarr, Prowlarr, qBittorrent, Jellyfin).

## Quick Start

1.  **Bootstrap Cluster:**
    ```bash
    ./bootstrap.sh
    ```

2.  **Access:**
    *   **Traefik Dashboard:** `https://192.168.1.111/dashboard/`
    *   **Argo CD:** `https://argo.epricesx.duckdns.org`
    *   **Nextcloud:** `https://nextcloud.epricesx.duckdns.org`
    *   **Media Apps (Ingress):**
        *   Sonarr: `https://sonarr.epricesx.duckdns.org`
        *   Radarr: `https://radarr.epricesx.duckdns.org`
        *   Prowlarr: `https://prowlarr.epricesx.duckdns.org`
        *   qBittorrent: `https://qbittorrent.epricesx.duckdns.org`
        *   Jellyfin: `https://jellyfin.epricesx.duckdns.org`
    *   **Media Apps (Direct IP):**
        *   Sonarr: `http://192.168.1.150:8989`
        *   Radarr: `http://192.168.1.151:7878`
        *   Prowlarr: `http://192.168.1.152:9696`
        *   qBittorrent: `http://192.168.1.153:8080`
        *   Jellyfin: `http://192.168.1.154:8096`

## Management

*   **Add App:** Create a new folder in `apps/<category>/<app-name>` with a Helm Chart.
*   **Update App:** Edit `values.yaml` and commit. Sync manually in Argo CD (auto-sync is currently disabled).
*   **Dependencies:** Helm charts use `version: "*"` to track the latest upstream versions.
*   **Secrets:** Managed in `apps/infra/secrets`.
*   **CronJobs:** Managed in `apps/infra/cronjobs`.