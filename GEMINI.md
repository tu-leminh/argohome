# GitOps Home Lab Project Specification

## 1. Project Overview
This project is a personal Home Lab orchestrating a diverse range of self-hosted applications using Kubernetes (K3s) and **GitOps** principles (Argo CD). The repository is the single source of truth.

## 2. Core Architecture
*   **Orchestrator:** K3s (Single Node: `dell`)
*   **GitOps Engine:** Argo CD (App of Apps pattern)
    *   **Bootstrap:** `bootstrap/applicationset.yaml` targets all subdirectories in `apps/`.
    *   **Sync Waves:** `core` (-5) -> `infra` (-1) -> `media` (5).
    *   **Sync Options:** `ServerSideApply=true` enabled to handle large CRDs (like ApplicationSet).
*   **Repository:** Private GitHub Repository (`gitops-home`)

## 3. Directory Structure
*   `bootstrap/`: The Argo CD ApplicationSet (Entry Point).
*   `apps/`:
    *   `core/`: System-critical apps (Argo CD, Homepage).
    *   `infra/`: Infrastructure services (MetalLB, Traefik, Secrets, Storage, Cronjobs).
    *   `media/`: Entertainment stack (Sonarr, Radarr, Prowlarr, Q1/Q2/Q3, Jellyfin).
    *   `nextcloud/`: Personal cloud storage.
    *   `tailscale/`: Mesh networking operator.

## 4. Technology Stack & Implementation

### Networking
*   **Load Balancing (Layer 2):** MetalLB
    *   **IP Pool:** `192.168.1.100 - 192.168.1.200`
    *   **Advertisement:** L2
*   **Ingress Controller:** Traefik
    *   Handles public/DDNS traffic.
    *   **Providers:** `DuckDNS`, `FreeMyIP`, `MyAddr`.
    *   **SSL:** Let's Encrypt / Custom Certs managed via Secrets.
*   **Mesh Networking:** Tailscale Operator
    *   **Mechanism:** Exposes services to the Tailnet via `Ingress` resources with `ingressClassName: tailscale`.
    *   **Config:** Managed via `apps/tailscale/operator`. Setup uses OAuth client secrets.

### Storage & Persistence
*   **Strategy:** **Stateless Compute, Stateful Host.**
    *   All persistent data resides on the host filesystem at `/data/apps/...`.
    *   Kubernetes resources mount these paths via `HostPath` PVs/PVCs defined in `apps/infra/storage`.
    *   **Node Affinity:** PVs are pinned to node `dell`.
*   **Key Paths:**
    *   **Media Shared:** `/data/apps/media/shared/{downloads,movies,shows}` (ReadWriteMany)
    *   **App Configs:** `/data/apps/{category}/{app_name}/config`

### Database Architecture

## 5. Operational Workflows
*   **Deploy New App:** Add a Helm chart to `apps/<category>/<name>`. The `ApplicationSet` automatically detects and deploys it.
*   **Updates:** Modify `values.yaml` or templates. Argo CD syncs automatically (or manually if configured).
*   **Secrets:** Managed as Kubernetes Secrets (Helm templates). *Caution: Ensure actual secrets are not committed in plain text if repo is public (currently private).*

## 6. Known Configurations & Fixes
*   **Argo CD Repo Server:** Requires explicit resource limits (`memory: 512Mi`) to prevent OOM kills during heavy syncs.
*   **Tailscale Ingress:** Must target the **HTTPS port (443)** for services enforcing HTTPS (Argo CD).
*   **Large CRDs:** `ServerSideApply` must be enabled in the ApplicationSet to support applying large CRDs like `applicationsets.argoproj.io`.

## 7. Agent Guidelines
*   **Verification:** Always run `helm template` locally to validate chart syntax before changes.
*   **Statelessness:** When modifying deployments, ensure no state is stored inside containers. Always check `apps/infra/storage` for PV definitions.
*   **Documentation:** Update this file and `README.md` if architectural decisions change.
