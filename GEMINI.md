# GitOps Home Lab Project Specification

## 1. Project Overview
This project is a Kubernetes-based Home Lab managed via **GitOps** (Argo CD). It uses the **"App of Apps"** pattern with an `ApplicationSet` to automatically discover and deploy Helm charts located in the `apps/` directory.

## 2. Core Architecture
* **Orchestrator:** MicroK8s (Single Node)
* **GitOps Engine:** Argo CD (Self-Managed)
* **Repository:** Private GitHub Repository (`gitops-home`)
* **Directory Structure:**
    * `bootstrap/`: Contains the `ApplicationSet` (The Entry Point).
    * `apps/`: Contains isolated Helm Charts for each workload.
        * `core/`: System-level apps (e.g., Argo CD wrapper).
        * `infra/`: Infrastructure layer (Storage, Networking, Secrets, CronJobs).
        * `media/`: Workload layer (Sonarr, Radarr, Prowlarr, qBittorrent, Jellyfin).
        * `cloud/`: Productivity layer (Nextcloud).

## 3. Technology Stack & Decisions
* **Networking:**
    * **MetalLB:** Provides Layer 2 LoadBalancing.
        *   **VIP:** `192.168.1.111` (Traefik Ingress)
        *   **Media Stack:** Direct LoadBalancer exposure with fixed IPs:
            *   Sonarr: `192.168.1.150`
            *   Radarr: `192.168.1.151`
            *   Prowlarr: `192.168.1.152`
            *   qBittorrent: `192.168.1.153`
            *   Jellyfin: `192.168.1.154`
    * **Traefik:** Ingress Controller handling SSL termination and routing.
        * **Strategy:** Split `IngressRoute` resources per cert resolver to support multiple dynamic DNS providers simultaneously.
        * **Cert Resolvers:** 
            * `letsencrypt` (DuckDNS)
            * `freemyip`
            * `myaddr`
    * **DNS:** DuckDNS, FreeMyIP, MyAddr.
* **Storage Strategy:**
    * **HostPath with Node Affinity:** Data resides on the host filesystem.
    * **Generic Media Volumes:**
        *   `downloads`: `/data/media/downloads`
        *   `movies`: `/data/media/movies`
        *   `shows`: `/data/media/tv`
    *   **Config Volumes:** Dedicated PVs for each app (e.g., `sonarr-config`, `qbittorrent-config`).
* **Secret Management:**
    * **Strategy:** Plain Kubernetes Secrets committed to Git (Base64 encoded).
    * **Implementation:** `apps/infra/secrets` generic chart replicates secrets to target namespaces (`infra`).
* **Dependency Management:**
    *   **Hybrid Approach:**
        *   **External Charts:** Some apps (e.g., `sonarr`) use external Helm dependencies (`pree` repo) with unpinned versions (`version: "*"`).
        *   **Pure Helm Templates:** Other apps (`radarr`, `prowlarr`, `qbittorrent`, `jellyfin`) use **pure local Helm templates** wrapping `linuxserver.io` Docker images. This avoids external chart dependency stability issues.
    *   **Chart Naming Convention:**
        *   Media charts are named `media-<appname>` (e.g., `media-sonarr`) to align with the `ApplicationSet` naming strategy (`<category>-<appname>`). This ensures clean resource naming (e.g., `metadata.name: media-sonarr`).
* **Automation:**
    * **CronJobs:** `apps/infra/cronjobs` generic chart handles DDNS updates (`duckdns`, `freemyip`, `myaddr`).

## 4. Operational Workflows
* **Bootstrap:** Run `./bootstrap.sh` to install MicroK8s, Argo CD, and configure private repo access.
* **Deployment:** Commit a new folder with `Chart.yaml` to `apps/` -> Argo CD auto-deploys it to a namespace matching its category.
    *   *Note:* Auto-sync is currently disabled in the `ApplicationSet` to allow for manual inspection/triggering of initial deployments.
* **Update:** Edit `values.yaml` or templates -> Commit -> Sync in Argo CD.

## 5. Agent Operational Rules
*   **Documentation:** Always update `README.md` and `GEMINI.md` after making changes to the codebase or architecture.
*   **Verification:** You **MUST** run `helm template` (and `helm dependency update` if applicable) on any modified or created Helm charts to verify syntax and rendering before confirming changes.