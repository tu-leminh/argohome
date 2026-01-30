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
        * `media/`: Workload layer (Sonarr, Radarr, etc.).

## 3. Technology Stack & Decisions
* **Networking:**
        *   **MetalLB:** Provides Layer 2 LoadBalancing (Static IP: `192.168.1.111`).
    * **Traefik:** Ingress Controller handling SSL termination and routing.
        * **Cert Resolvers:** 
            * `letsencrypt` (DuckDNS)
            * `freemyip`
            * `myaddr`
    * **DNS:** DuckDNS, FreeMyIP, MyAddr.
* **Storage Strategy:**
    * **HostPath with Node Affinity:** Data resides on the host filesystem (`/data/...`).
    * **Resilience:** PVs are pinned to the node hostname.
* **Secret Management:**
    * **Strategy:** Plain Kubernetes Secrets committed to Git (Base64 encoded).
    * **Implementation:** `apps/infra/secrets` generic chart replicates secrets to target namespaces (`infra`).
* **Automation:**
    * **CronJobs:** `apps/infra/cronjobs` generic chart handles DDNS updates (`duckdns`, `freemyip`, `myaddr`).

## 4. Operational Workflows
* **Bootstrap:** Run `./bootstrap.sh` to install MicroK8s, Argo CD, and configure private repo access.
* **Deployment:** Commit a new folder with `Chart.yaml` to `apps/` -> Argo CD auto-deploys it to a namespace matching its category (e.g., `apps/media/sonarr` -> `media`).
* **Update:** Edit `values.yaml` -> Commit -> Argo CD syncs.