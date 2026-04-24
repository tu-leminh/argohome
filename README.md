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
`bootstrap/applicationset.yaml` scans every directory under `apps/*/*` and creates an Argo CD Application for each. Apps are deployed in sync waves:

| Wave | Namespace | What |
|---|---|---|
| -5 | `core` | Argo CD, Homepage |
| -1 | `infra` | MetalLB, Traefik, Secrets, Storage, Scripts |
| 5 | `media` | All media apps |
| — | `nextcloud` | Nextcloud + CNPG database |
| — | `tailscale` | Tailscale operator |

### Networking
- **MetalLB** — Layer 2 LoadBalancer, IP pool `192.168.1.100–200`
- **Traefik** — Ingress + SSL (Let's Encrypt via DuckDNS / FreeMyIP / MyAddr DNS challenges), LoadBalancer IP `192.168.1.111`
- **Tailscale Operator** — Private mesh access via `Ingress` resources (`ingressClassName: tailscale`)

Services are reachable three ways:
1. **LAN** — Direct MetalLB IP (e.g. `192.168.1.156` for Qui)
2. **DDNS** — `https://<app>.epricesx.duckdns.org`
3. **Tailscale** — `https://<app>.platy-python.ts.net`

### Storage
All persistent data on the host at `/data/`:

| Path | Contents |
|---|---|
| `/data/shared/downloads` | Shared torrent downloads (RWX) |
| `/data/shared/movies` | Movies library (RWX) |
| `/data/shared/shows` | TV shows library (RWX) |
| `/data/configs/<app>` | Per-app config directories |

PVs are HostPath, pinned to node `dell` via node affinity. Defined in `apps/infra/storage/values.yaml`.

### Security Context
Apps that own their config dirs run with `runAsUser: 1000 / runAsGroup: 1000 / fsGroup: 1000` to match the host filesystem ownership set by the `perm-fixer` cron job.

> **Note:** Only use `PUID`/`PGID` env vars for **LinuxServer.io** images. Non-LinuxServer images (e.g. `ghcr.io/autobrr/qui`) ignore those vars — use `securityContext` instead.

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
| Q2 | `linuxserver/qbittorrent` | 8080 | 192.168.1.158 |
| Q3 | `linuxserver/qbittorrent` | 8080 | 192.168.1.159 |
| Jellyfin | `linuxserver/jellyfin` | 8096 | 192.168.1.155 |
| Bazarr | `linuxserver/bazarr` | 6767 | — |

### Cloud
| App | Description |
|---|---|
| Nextcloud | Personal cloud (CNPG PostgreSQL backend) |

## Deploying a New App

1. Create `apps/<category>/<name>/` with a Helm chart
2. Commit and push
3. Argo CD detects and deploys it automatically

## Troubleshooting

| Problem | Fix |
|---|---|
| Argo CD sync stuck | Check `repo-server` memory limits; large CRDs need `ServerSideApply=true` |
| App can't write to config dir | Ensure `securityContext.runAsUser: 1000` — perm-fixer chowns all `/data/configs/*` to UID 1000 |
| Qui first-run setup | After first deploy, exec into pod and run `qui create-user` |
| Traefik cert not issued | Check DDNS token secrets; ACME files must be `chmod 600` owned by UID 1000 |
