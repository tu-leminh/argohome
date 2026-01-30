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
    *   `infra/`: Infrastructure (Traefik, MetalLB, Secrets, CronJobs).
    *   `media/`: Media apps (Sonarr).

## Quick Start

1.  **Bootstrap Cluster:**
    ```bash
    ./bootstrap.sh
    ```

2.  **Access:**
    *   **Traefik Dashboard:**
        *   `https://192.168.1.111/dashboard/`
        *   `https://traefik.epricesx.duckdns.org/dashboard/`
        *   `https://traefik.lmtu.freemyip.com/dashboard/`
    *   **Argo CD:**
        *   `https://192.168.1.111`
        *   `https://argo.epricesx.duckdns.org`
    *   **Sonarr:** `https://sonarr.epricesx.duckdns.org`

## Management

*   **Add App:** Create a new folder in `apps/<category>/<app-name>` with a Helm Chart.
*   **Update App:** Edit `values.yaml` and commit. Argo CD handles the rest.
*   **Secrets:** Managed in `apps/infra/secrets`.
*   **CronJobs:** Managed in `apps/infra/cronjobs`.