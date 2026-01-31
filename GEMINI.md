# GitOps Home Lab Project Specification

## 1. Project Overview
This project is a personal Home Lab orchestrating a diverse range of self-hosted applications using Kubernetes and **GitOps** principles. The system uses MicroK8s as the foundation and Argo CD to drive the cluster state from this Git repository.

## 2. Core Architecture
*   **Orchestrator:** MicroK8s (Single Node)
*   **GitOps Engine:** Argo CD (App of Apps pattern)
*   **Repository:** Private GitHub Repository (`gitops-home`)
*   **Directory Structure:**
    *   `bootstrap/`: The Argo CD ApplicationSet (Entry Point).
    *   `apps/`: Helm charts organized by functional layer.
        *   `core/`: System-critical apps (Argo CD).
        *   `infra/`: Infrastructure services (Networking, Storage, Databases, Secrets).
        *   `media/`: Entertainment stack (Sonarr, Radarr, Prowlarr, qBittorrent, Jellyfin).
        *   `cloud/`: Productivity suite (Nextcloud).

## 3. Technology Stack & Implementation

### Networking
*   **Load Balancing (Layer 2):** MetalLB
    *   **VIP:** `192.168.1.111` (Cluster Entry Point)
    *   **Direct Media Access:** Dedicated IPs for each media application (e.g., Sonarr on `.150`, Radarr on `.151`).
*   **Ingress Controller:** Traefik
    *   Handles SSL termination and routing via `IngressRoute` CRDs.
    *   Supports multiple dynamic DNS providers simultaneously (`DuckDNS`, `FreeMyIP`, `MyAddr`).
*   **DNS Strategy:**
    *   External: Dynamic DNS updates via CronJobs.
    *   Internal: Split IngressRoutes per provider.

### Storage & Persistence
*   **Strategy:** **Stateless Compute, Stateful Host.**
    *   All persistent data resides on the host filesystem (`/data/...`).
    *   Kubernetes resources mount these paths via `HostPath` PVs/PVCs.
    *   **Goal:** Complete cluster disposability. If the cluster is reset, simply re-apply manifests to reconnect to existing data.
*   **Volume Mapping:**
    *   **Media:** `/data/apps/media/shared/{downloads,movies,shows}`
    *   **Configs:** `/data/apps/{category}/{app_name}/config`
    *   **Database:** `/data/apps/infra/postgres-operator/data`
    *   **Nextcloud Data:** `/data/apps/nextcloud/nextcloud/data`

### Database Architecture
*   **PostgreSQL:**
    *   Deployed as a standard Deployment (Single Instance).
    *   **User Strategy:** Uses the default `postgres` superuser for all connections.
        *   *Why?* To ensure seamless reconnection to existing data after cluster resets without permission conflicts.
    *   **Authentication:** `nextcloudpassword` (Shared secret).

### Application Layer
*   **Media Stack:**
    *   Pure local Helm templates wrapping `linuxserver.io` images.
    *   Direct IP exposure for local network usage + Ingress for remote.
*   **Nextcloud:**
    *   Dedicated Helm chart.
    *   Connects to the shared Postgres instance in `infra` namespace.
    *   Environment variables enforce `DB_USER: postgres` for reliable init.

## 4. Operational Workflows
*   **Bootstrap:** Execute `./bootstrap.sh` to initialize MicroK8s and Argo CD.
*   **Deploy New App:** Add a Helm chart to `apps/<category>/<name>`. The `ApplicationSet` automatically detects and deploys it.
*   **Updates:** Modify `values.yaml` or templates in the repo. Argo CD syncs the changes (Manual trigger enabled).
*   **Cluster Reset:**
    1.  Tear down MicroK8s.
    2.  Ensure host data paths (`/data/...`) are intact (or clean if a fresh start is desired).
    3.  Run `./bootstrap.sh`.
    4.  Argo CD restores all apps, which reconnect to the host data.

## 5. Agent Guidelines
*   **Verification:** Always run `helm template` locally to validate chart syntax before changes.
*   **Statelessness:** When modifying deployments, ensure no state is stored inside containers. Always check `apps/infra/storage` for PV definitions.
*   **Documentation:** Update this file and `README.md` if architectural decisions change.
