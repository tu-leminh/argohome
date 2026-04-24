# GitOps Home Lab — Agent Reference

## 1. Project Overview
Personal home lab running self-hosted apps on **K3s** (single node: `dell`) managed via **Argo CD** GitOps. This repo is the single source of truth.

## 2. Core Architecture

### GitOps Engine
- **ApplicationSet:** `bootstrap/applicationset.yaml` — scans `apps/*/*`, creates one Argo CD Application per directory
- **App naming:** `{{path[1]}}-{{path.basename}}` (e.g. `media-qui`, `infra-traefik`)
- **Namespace:** equals `path[1]` (e.g. `media`, `infra`, `core`)
- **Sync:** automated with `prune: true`, `selfHeal: true`, `ServerSideApply: true`
- **Sync waves:** `core` (-5) → `infra` (-1) → `media` (5)

### Node
- Single node cluster: hostname `dell`, Kubernetes node name `dell`
- All PVs use HostPath with `nodeAffinity` pinned to `dell`

## 3. Directory Structure

```
apps/
  core/          # Argo CD, Homepage
  infra/         # MetalLB, Traefik, CNPG, Secrets, Storage, Scripts
  media/         # All media apps
  nextcloud/     # Nextcloud + CNPG DB
  tailscale/     # Tailscale operator
bootstrap/       # ApplicationSet entry point
```

Each app is a standalone Helm chart with `Chart.yaml`, `values.yaml`, and `templates/`.

## 4. Networking

| Layer | Tool | Config |
|---|---|---|
| L2 LoadBalancer | MetalLB | IP pool `192.168.1.100–200` |
| Ingress + TLS | Traefik | LB IP `192.168.1.111`, ACME via DuckDNS/FreeMyIP/MyAddr |
| Private mesh | Tailscale operator | `ingressClassName: tailscale`, Funnel enabled |

**Ingress patterns per app:**
- `templates/ingressroute.yaml` — Traefik `IngressRoute` CRD (external DDNS)
- `templates/ingress-tailscale.yaml` — `networking.k8s.io/v1 Ingress` with `ingressClassName: tailscale`

**DDNS providers:** DuckDNS (`epricesx`), FreeMyIP (`lmtu.freemyip.com`), MyAddr (`lmtlmt.myaddr.io`)

## 5. Storage

All data on host under `/data/`:
- **Shared media:** `/data/shared/{downloads,movies,shows}` — RWX
- **App configs:** `/data/configs/<app>` — RWO

PVs/PVCs defined in `apps/infra/storage/values.yaml`. Template at `apps/infra/storage/templates/pv-pvc.yaml`.

## 6. Security Context & UID Rules

**Critical rule:** The `perm-fixer` cron job runs `chown -R 1000:1000` on all `/data/configs/*` directories (except `nextcloud-db` and `nextcloud-app`).

### Consequence for app deployments:
- **LinuxServer.io images** (`lscr.io/linuxserver/*`): pass `PUID: "1000"` and `PGID: "1000"` env vars — the image's init script drops to that UID internally.
- **Non-LinuxServer images** (e.g. `ghcr.io/autobrr/qui`, `ghcr.io/autobrr/autobrr`): `PUID`/`PGID` env vars are **ignored**. Use pod `securityContext` instead:
  ```yaml
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  ```
- **Special cases** (postgres via CNPG runs as UID 26, Nextcloud-app www-data UID 33): add to the `SKIP` list in `perm-fixer.sh`.

## 7. Scripts / CronJobs (`apps/infra/scripts`)

| Job | Schedule | Purpose |
|---|---|---|
| `duckdns-updater` | `*/20 * * * *` | Update DuckDNS DDNS record |
| `freemyip-updater` | `5-59/20 * * * *` | Update FreeMyIP DDNS record |
| `myaddr-updater` | `10-59/20 * * * *` | Update MyAddr DDNS record |
| `perm-fixer` | `0 * * * *` | `chown -R 1000:1000` on `/data/configs/*` (excludes nextcloud-db, nextcloud-app) |
| `tailscale-cleanup` | `0 4 * * *` | Remove stale Tailscale devices |

All jobs also run on Argo CD sync via `job-on-sync.yaml`.

## 8. Known Issues & Fixes

### Non-LinuxServer images and UID 1000
`ghcr.io/autobrr/qui` and similar images do not process `PUID`/`PGID`. They must be deployed with `securityContext.runAsUser: 1000` so file ownership matches what `perm-fixer` sets. Without this, the app runs as root, creates files owned by root, and after perm-fixer runs ownership is inconsistent — leading to a silent `exit code 1` on next startup.

### Qui first-run
After deploying Qui for the first time (empty config dir), exec into the pod and run:
```bash
qui create-user
```
The server will not accept logins until a user exists.

### Traefik ACME files
Must be `chmod 600` and owned by UID 1000. Enforced by `perm-fixer.sh`.

### Argo CD large CRDs
`ServerSideApply=true` is required in the ApplicationSet to apply large CRDs like `applicationsets.argoproj.io`.

### Argo CD repo-server OOM
Set memory limit to at least `512Mi` on the `repo-server` deployment.

### Tailscale ingress
For services that enforce HTTPS (e.g. Argo CD), the Tailscale `Ingress` backend must target port **443**, not the app's HTTP port.

## 9. Agent Guidelines

1. **Validate before pushing:** Run `helm template apps/<category>/<app>` to catch syntax errors.
2. **Check storage first:** Before adding a new app, add its PV/PVC to `apps/infra/storage/values.yaml`.
3. **UID rule:** Check whether the image is LinuxServer before choosing between `PUID/PGID` env vars vs `securityContext`.
4. **Update this file** if architecture, UID rules, or known issues change.
5. **Verification:** After pushing, confirm with `kubectl get pod -n <ns> -l app.kubernetes.io/name=<name>` and `kubectl get application -n core <name> -o jsonpath='{.status.sync.status} {.status.health.status}'`.
