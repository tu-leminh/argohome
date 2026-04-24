# GitOps Home Lab

A self-healing home server powered by **K3s** and **Argo CD**.

## Overview

All infrastructure is defined as code in this repo. Argo CD watches it and keeps the cluster in sync automatically. The cluster node (`dell`) can be wiped and rebuilt without losing application data — everything persistent lives on the host filesystem under `/data/`.

## Quick Start

### Bootstrap
```bash
./bootstrap.sh
```

### Access
| Service | URL |
|---|---|
| Homepage | `https://epricesx.duckdns.org` |
| Argo CD | `https://argo.epricesx.duckdns.org` |

Argo CD password: `kubectl -n core get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

## Architecture

### GitOps (App of Apps)
`bootstrap/applicationset.yaml` scans every directory under `apps/*/*` and creates an Argo CD Application for each. App name = `{category}-{dirname}`, namespace = `{category}`. Sync is fully automated (`prune: true`, `selfHeal: true`, `ServerSideApply: true`).

Apps are deployed in sync waves:

| Wave | Namespace | What |
|---|---|---|
| -5 | `core` | Argo CD, Homepage |
| -1 | `infra` | MetalLB, Traefik, Secrets, Storage, Scripts |
| 5 | `media` | All media apps |
| — | `nextcloud` | Nextcloud + CNPG database |
| — | `tailscale` | Tailscale operator |

Each app is a standalone Helm chart with `Chart.yaml`, `values.yaml`, and `templates/`. Helm artifacts (`*.lock`, `*.tgz`) are gitignored.

### Networking
- **MetalLB** — Layer 2 LoadBalancer, IP pool `192.168.1.100–200`
- **Traefik** — Ingress + SSL (Let's Encrypt via DuckDNS / FreeMyIP / MyAddr DNS challenges), LoadBalancer IP `192.168.1.111`
- **Tailscale Operator** — Private mesh access via `Ingress` resources (`ingressClassName: tailscale`, Funnel enabled)

Services are reachable three ways:
1. **LAN** — Direct MetalLB IP (e.g. `192.168.1.156` for Qui)
2. **DDNS** — `https://<app>.epricesx.duckdns.org`
3. **Tailscale** — `https://<app>.platy-python.ts.net`

**Ingress patterns per app:**
- `templates/ingressroute.yaml` — Traefik `IngressRoute` CRD (external DDNS)
- `templates/ingress-tailscale.yaml` — `networking.k8s.io/v1 Ingress` with `ingressClassName: tailscale`

**DDNS providers:** DuckDNS (`epricesx`), FreeMyIP (`lmtu.freemyip.com`), MyAddr (`lmtlmt.myaddr.io`)

### Storage
All persistent data on the host at `/data/`. PVs are HostPath, pinned to node `dell` via node affinity. Defined in `apps/infra/storage/values.yaml`.

| Path | Contents | Mode |
|---|---|---|
| `/data/shared/downloads` | Shared torrent downloads | RWX |
| `/data/shared/movies` | Movies library | RWX |
| `/data/shared/shows` | TV shows library | RWX |
| `/data/configs/<app>` | Per-app config directories | RWO |

### Security Context & UID Rules

The `perm-fixer` cron job runs `chown -R 1000:1000` hourly on all `/data/configs/*` (except `nextcloud-db` and `nextcloud-app`). Apps must therefore run as UID 1000:

- **LinuxServer.io images** (`lscr.io/linuxserver/*`): pass `PUID: "1000"` and `PGID: "1000"` env vars — the image's init script drops to that UID internally.
- **Non-LinuxServer images** (e.g. `ghcr.io/autobrr/qui`, `ghcr.io/autobrr/autobrr`): `PUID`/`PGID` env vars are **ignored**. Use pod `securityContext` instead:
  ```yaml
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  ```
- **Special cases** (CNPG postgres UID 26, Nextcloud www-data UID 33): these are in the `SKIP` list in `perm-fixer.sh`.

## Scripts / CronJobs (`apps/infra/scripts`)

| Job | Schedule | Purpose |
|---|---|---|
| `duckdns-updater` | `*/20 * * * *` | Update DuckDNS DDNS record |
| `freemyip-updater` | `5-59/20 * * * *` | Update FreeMyIP DDNS record |
| `myaddr-updater` | `10-59/20 * * * *` | Update MyAddr DDNS record |
| `perm-fixer` | `0 * * * *` | `chown -R 1000:1000` on `/data/configs/*` (excludes nextcloud-db, nextcloud-app) |
| `tailscale-cleanup` | `0 4 * * *` | Remove stale Tailscale devices |

All jobs also run on Argo CD sync via `job-on-sync.yaml`.

## Applications

### Core
| App | Description |
|---|---|
| Argo CD | GitOps controller |
| Homepage | Dashboard |

### Infrastructure
| App | Description |
|---|---|
| MetalLB | L2 LoadBalancer |
| Traefik | Ingress + TLS |
| CNPG | CloudNativePG operator (Nextcloud DB) |
| Secrets | Kubernetes Secret manifests |
| Storage | PV/PVC definitions |
| Scripts | CronJobs: DDNS updaters, perm-fixer, Tailscale cleanup |

### Media Stack
| App | Image | Port | LAN IP |
|---|---|---|---|
| Seerr | `linuxserver/overseerr` | 5055 | 192.168.1.150 |
| Sonarr | `linuxserver/sonarr` | 8989 | 192.168.1.151 |
| Radarr | `linuxserver/radarr` | 7878 | 192.168.1.152 |
| Prowlarr | `linuxserver/prowlarr` | 9696 | 192.168.1.153 |
| Autobrr | `ghcr.io/autobrr/autobrr` | 7474 | 192.168.1.154 |
| Qui | `ghcr.io/autobrr/qui` | 7476 | 192.168.1.156 |
| Q1 | `linuxserver/qbittorrent` | 8080 | 192.168.1.157 |
| Q2 | `linuxserver/qbittorrent` | 8080 | 192.168.1.165 |
| Q3 | `linuxserver/qbittorrent` | 8080 | 192.168.1.166 |
| Jellyfin | `linuxserver/jellyfin` | 8096 | 192.168.1.155 |
| Bazarr | `linuxserver/bazarr` | 6767 | — |

### Cloud
| App | Description |
|---|---|
| Nextcloud | Personal cloud (CNPG PostgreSQL backend) |

## Deploying a New App

1. Create `apps/<category>/<name>/` as a Helm chart.
2. Add its PV/PVC to `apps/infra/storage/values.yaml` before the app deploys.
3. Add `templates/ingressroute.yaml` (Traefik DDNS) and `templates/ingress-tailscale.yaml` (VPN mesh).
4. Commit and push — Argo CD detects and deploys automatically.

**Step 1 — validate before pushing (required):**
```bash
helm template apps/<category>/<app>
```

**Step 2 — after pushing, wait up to 3 minutes for Argo CD to poll git, then verify (required):**
```bash
# Expected: Synced Healthy
kubectl get application -n core <app-name> -o jsonpath='{.status.sync.status} {.status.health.status}'

# Expected: pod Running
kubectl get pod -n <namespace> -l app.kubernetes.io/name=<name>

# If something is wrong
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name>
```

> Do not manually trigger `argocd app sync` — push to git and let Argo CD reconcile. That's the point.

## Troubleshooting

| Problem | Fix |
|---|---|
| Argo CD sync stuck on large CRDs | `ServerSideApply=true` is set in the ApplicationSet; check `repo-server` memory (≥ `512Mi`) |
| App can't write to config dir | Ensure `securityContext.runAsUser: 1000` — perm-fixer chowns all `/data/configs/*` to UID 1000 |
| Non-LinuxServer image running as root | `PUID`/`PGID` env vars are silently ignored; use `securityContext` instead |
| Qui first-run setup | After first deploy, exec into pod and run `qui create-user` |
| Traefik cert not issued | Check DDNS token secrets; ACME files must be `chmod 600` owned by UID 1000 |
| Tailscale ingress for HTTPS service | Backend port must be `443`, not the app's HTTP port |

## Known Issues & Improvements

### Critical

**Secrets committed in plaintext**
`apps/infra/secrets/values.yaml` stores DDNS tokens and Tailscale credentials as base64, which is encoding not encryption — trivially reversible. If this repo is ever public or leaked, those tokens are compromised. Migrate to `git-crypt`, Sealed Secrets, or inject tokens at bootstrap time outside of git.

**Traefik dashboard exposed unauthenticated**
`apps/infra/traefik/values.yaml` passes `--api.insecure=true`, exposing the Traefik dashboard on port 8080 with no authentication. Anyone on the LAN can read routing rules and middleware config. Either remove the flag or protect the dashboard behind an IngressRoute with auth middleware.

### High

**Sonarr uses an unpinned 3rd-party upstream chart**
`apps/media/sonarr/Chart.yaml` pulls from `https://pree.github.io/helm-charts` with `version: "*"`. Every other media app has its own `deployment.yaml`/`service.yaml`. An upstream breaking change will deploy automatically. The LoadBalancer IP is not explicitly set in `values.yaml`, so the LAN IP in the table above may not actually be assigned.

**All images pinned to `latest` with `pullPolicy: Always`**
Every media app and all infra scripts (`alpine:latest`, `curlimages/curl:latest`) use `latest`. A pod restart after an upstream breaking release silently breaks the stack. Pin to specific SemVer tags.

**No resource limits or health probes**
No `resources`, `livenessProbe`, or `readinessProbe` on any deployment. A hung or OOM'd pod won't be automatically restarted or evicted.

**No backup for `/data/`**
All persistent state is HostPath on a single node (`dell`) with no backup CronJob or documented recovery procedure. A drive failure loses all application state.

### Medium

**Duplicate code across media app charts**
All 11 media charts share ~90% identical `deployment.yaml`, `_helpers.tpl`, and ingress templates with minor variations. Consider a shared base chart or a Helm library chart to reduce drift.

**No CI validation**
No `helm lint`, `helm template`, or manifest validation runs before changes merge. Errors are caught only after Argo CD attempts to sync. A pre-commit hook running `helm template apps/<category>/<app>` would catch most issues early.

**CNPG `nextcloud-db-app` secret is undocumented**
`apps/nextcloud/nextcloud/templates/deployment.yaml` references secret `nextcloud-db-app` which is created by CNPG, not by this repo. This implicit dependency is not documented anywhere and will cause the Nextcloud pod to crash on a fresh cluster until CNPG finishes bootstrapping.

### Low

**Homepage dashboard links are hardcoded**
`apps/core/homepage/values.yaml` hardcodes all service URLs. Adding a new app requires manually updating this config — it won't auto-discover new Argo CD applications.
