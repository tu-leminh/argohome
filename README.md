# GitOps Home Lab

A self-healing home server powered by **K3s** and **Argo CD**.

## Overview

All infrastructure is defined as code in this repo. Argo CD watches it and keeps the cluster in sync automatically. The cluster node (`dell`) can be wiped and rebuilt without losing application data — everything persistent lives on the host filesystem under `/data/`.

## Quick Start

### Bootstrap

Plain steps that work on any cluster; nothing in this repo depends on how they
are run. (On the home server, the `homelab-bootstrap` unit in the
[nix flake](https://github.com/tu-leminh/nix) automates exactly these.)

Prerequisites: a k3s/Kubernetes cluster with Cilium as the CNI (with
kube-proxy replacement, L2 announcements and Gateway API, which
`apps/infra/network` builds on), plus `kubectl`, `helm` and a read-only deploy
key for this repo.

```bash
# 1. Argo CD. The release name MUST be infra-argocd in namespace infra: the
#    chart derives resource names and the instance label from it, and the
#    self-managed apps/infra/argocd render must match to adopt these resources.
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install infra-argocd argo/argo-cd \
  --namespace infra --create-namespace \
  --set server.service.type=LoadBalancer \
  --set server.insecure=true

# 2. Repository credential (private repo, SSH deploy key).
kubectl -n infra create secret generic repo-argohome \
  --from-literal=type=git \
  --from-literal=url=git@github.com:tu-leminh/argohome.git \
  --from-file=sshPrivateKey=$HOME/.ssh/id_ed25519
kubectl -n infra label secret repo-argohome argocd.argoproj.io/secret-type=repository

# 3. Everything else: the App-of-Apps ApplicationSet.
kubectl apply -f bootstrap/applicationset.yaml
```

Argo CD then deploys every chart under `apps/*/*`, including itself. OpenBao
initializes and unseals itself (`apps/infra/openbao/README.md`), and External
Secrets fills the app Secrets from it. On a brand-new cluster OpenBao starts
empty, so write the `secret/homelab/*` values listed in that README before the
DDNS, Tailscale and slskd apps can work.

### Access
| Service | URL |
|---|---|
| Homepage | `https://epricesx.duckdns.org` |
| Argo CD | `https://argo.epricesx.duckdns.org` |

Argo CD password: `kubectl -n infra get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

## Operating Rules (must follow)

- **GitOps**: never create/edit/delete Kubernetes resources manually — commit, push, and let Argo CD reconcile. That's the point.
- **KISS (Keep It Simple, Stupid)** — this is a single-node homelab: prefer the simplest option that works. Favor boring, well-trodden choices over clever ones; only deviate when there's a documented reason (e.g. `privileged: true` for Jellyfin GPU passthrough, see `apps/media/jellyfin/values.yaml`).
- **Document host-side workarounds**: every NixOS host workaround must ship with a short comment explaining *why* it exists plus the upstream bug/driver reference to monitor, so it can be revisited when upstream fixes it — e.g. the `amdgpu.ppfeaturemask=0xFFFF7FFF` VCN hang fix (drm/amd#3400, jellyfin#12186) in `hosts/homelab/default.nix`.

## Architecture

### GitOps (App of Apps)
`bootstrap/applicationset.yaml` scans every directory under `apps/*/*` and creates an Argo CD Application for each. App name = `{category}-{dirname}`, namespace = `{category}`. Sync is fully automated (`prune: true`, `selfHeal: true`, `ServerSideApply: true`).

Apps are deployed in sync waves:

| Wave | Namespace | What |
|---|---|---|
| -5 | `infra` | Argo CD, Homepage |
| -1 | `infra` | Network, Lego, OpenBao, Secrets, Storage, Scripts, Tailscale operator |
| 5 | `media` | All media apps |

Each app is a standalone Helm chart with `Chart.yaml`, `values.yaml`, and `templates/`. Helm artifacts (`*.lock`, `*.tgz`) are gitignored.

### Networking
- **Cilium** — cluster CNI + kube-proxy replacement (eBPF dataplane), dual-stack (IPv4/IPv6)
- **Cilium LB-IPAM + L2 Announcements** (`apps/infra/network`) — Layer 2 LoadBalancer,
  replaces MetalLB. IP pool `10.0.1.3–255` (a /24 carved out of the home `10.0.0.0/16`
  LAN; keep it out of the router's DHCP range). Every Service is dual-stack: a
  LoadBalancer at `10.0.1.N` also gets the public `<ISP /64>::1:N`, kept current by
  `ipv6-prefix-sync`. IPv6 has no NAT, so these are reachable from the internet unless the
  router's IPv6 firewall filters them
- **Cilium Gateway API** (`apps/infra/network`) — reverse proxy (Ingress + SSL), replaces
  Traefik. TLS certs come from `apps/infra/lego`'s DNS-01 Secrets (Let's Encrypt via
  DuckDNS / FreeMyIP / MyAddr DNS challenges); Gateway LoadBalancer IPs `10.0.1.2` and
  `<ISP /64>::1:2`. The ISP's IPv6 prefix is dynamic, so the `ipv6-prefix-sync` CronJob
  re-reads it from the node every 5 minutes and moves every IPv6 address with it; the DDNS
  updaters publish the Gateway's as the AAAA record
- **WAN** — the router forwards 80/443 on its public IPv4 to the Gateway's `10.0.1.2`; on
  IPv6 the Gateway's address is directly reachable (no NAT)
- **Tailscale Operator** — Private mesh access via `Ingress` resources (`ingressClassName: tailscale`, Funnel enabled)

Services are reachable three ways:
1. **LAN** — every HTTP app has its own dedicated LoadBalancer IP from `10.0.1.0/24` on
   **port 80**: `http://10.0.1.<n>` (see table below). The Gateway at `10.0.1.2` serves all
   DDNS hostnames on 443 via SNI/Host routing (its port 80 redirects to HTTPS)
2. **DDNS** — `https://<app>.epricesx.duckdns.org` (WAN → router → Gateway, IPv4 and IPv6)
3. **Tailscale** — `https://<app>.platy-python.ts.net`

**Ingress patterns per app:**
- `templates/httproute.yaml` — Gateway API `HTTPRoute` (external DDNS, attaches to
  `infra-gateway` from `apps/infra/network`)
- `templates/ingress-tailscale.yaml` — `networking.k8s.io/v1 Ingress` with `ingressClassName: tailscale`

**DDNS providers:** DuckDNS (`epricesx`), FreeMyIP (`lmtu.freemyip.com`), MyAddr (`lmtlmt.myaddr.io`)

### Storage
All persistent data on the host at `/data/`. PVs are HostPath, pinned to node `homelab` via node affinity. Defined in `apps/infra/storage/values.yaml`.

| Path | Contents | Mode |
|---|---|---|
| `/data/tier3/shared/downloads` | Shared torrent downloads | RWX |
| `/data/tier3/shared/movies` | Movies library | RWX |
| `/data/tier3/shared/shows` | TV shows library | RWX |
| `/data/tier3/shared/music` | Music library | RWX |
| `/data/tier2/configs/<app>` | Per-app config directories | RWO |

### Security Context & UID Rules

hostPath directories are auto-created `root:root` by kubelet/containerd and `fsGroup` is ignored on hostPath PVs. Apps run as UID 1000, so each one needs a root `initContainer` (`busybox`, `runAsUser: 0`) that `chown -R 1000:1000`s its config mount before the app starts (see `apps/media/qui`). The host has no chown watcher unit.

- **LinuxServer.io images** (`lscr.io/linuxserver/*`): pass `PUID: "1000"` and `PGID: "1000"` env vars — the image's init script drops to that UID internally.
- **Non-LinuxServer images** (e.g. `ghcr.io/autobrr/qui`, `ghcr.io/autobrr/autobrr`): `PUID`/`PGID` env vars are **ignored**. Use pod `securityContext` instead:
  ```yaml
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  ```

## Scripts / CronJobs (`apps/infra/scripts`)

| Job | Schedule | Purpose |
|---|---|---|
| `duckdns-updater` | `*/20 * * * *` | Update DuckDNS DDNS record |
| `freemyip-updater` | `5-59/20 * * * *` | Update FreeMyIP DDNS record |
| `myaddr-updater` | `10-59/20 * * * *` | Update MyAddr DDNS record |

The `infra-tailscale` app also exposes a suspended `tailscale-cleanup` CronJob. It is
not coupled to operator rollouts and does not run automatically. To remove
operator proxy devices (`tag:k8s`) on demand:

```bash
kubectl -n infra create job tailscale-cleanup-manual-$(date +%s) \
  --from=cronjob/tailscale-cleanup
```

### Triggering a lego cert issuance on demand

`apps/infra/lego` runs `lego-duckdns`, `lego-freemyip`, and `lego-myaddr` CronJobs every 15
minutes (`*/15 * * * *`) — `lego run` is a cheap no-op (no ACME/DNS-provider calls) until a
cert is within its renewal window, so on a fresh cluster the first real issuance happens
automatically within 15 minutes with no manual step. To force it sooner:

```bash
kubectl create job --from=cronjob/lego-duckdns lego-duckdns-manual -n infra
```

Wait and stream logs (use pod name, not label selector):
```bash
until kubectl get pod -n infra -l job-name=lego-duckdns-manual --no-headers | grep -qE "Running|Completed|Error"; do sleep 2; done
POD=$(kubectl get pod -n infra -l job-name=lego-duckdns-manual -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n infra $POD -f
```

Clean up when done, and repeat for `lego-freemyip`/`lego-myaddr`:
```bash
kubectl delete job lego-duckdns-manual -n infra
```

## Applications

### Infrastructure (namespace `infra`)
| App | Description |
|---|---|
| Argo CD | GitOps controller |
| Homepage | Dashboard |
| Network | `CiliumLoadBalancerIPPool`/`CiliumL2AnnouncementPolicy` (replaces MetalLB) + Cilium `Gateway`/`GatewayClass`/redirect `HTTPRoute` (replaces Traefik) |
| Lego | Daily CronJobs issuing ACME DNS-01 certs into `*-tls` Secrets (duckdns/freemyip/myaddr), consumed by the Gateway's listeners |
| OpenBao | Secrets store (standalone, file-backed on `/data/tier1/openbao`); see `apps/infra/openbao/README.md` |
| External Secrets | External Secrets Operator + `ClusterSecretStore` `openbao` (Kubernetes auth, role `eso-read`); syncs OpenBao KV into Secrets |
| AdGuard | AdGuard Home DNS resolver, LAN-only on `10.0.1.20` (DNS 53/UDP+TCP, UI :80, first-run wizard :3000); no public route |
| Secrets | `ExternalSecret`s that sync OpenBao `secret/homelab/*` into the DDNS and Tailscale Secrets (no values in git) |
| Storage | PV/PVC definitions |
| Scripts | CronJobs: DDNS updaters |
| Tailscale | Tailscale Kubernetes operator — private mesh `Ingress` support, plus the `homelab-exit` exit node (`Connector`; approve it once in the Tailscale admin console) |

### Media Stack
| App | Image | Port | LAN IP (LB, :80) |
|---|---|---|---|
| Seerr | `linuxserver/overseerr` | 5055 | 10.0.1.15 |
| Sonarr | `linuxserver/sonarr` | 8989 | 10.0.1.16 |
| Radarr | `linuxserver/radarr` | 7878 | 10.0.1.14 |
| Prowlarr | `linuxserver/prowlarr` | 9696 | 10.0.1.9 |
| Lidarr | `linuxserver/lidarr:nightly` (Plugins branch — [supports Tubifarry](https://wiki.servarr.com/en/lidarr/plugins)) | 8686 | 10.0.1.8 |
| Slskd | `slskd/slskd` ([Soulseek daemon](https://github.com/slskd/slskd)) | 5030 (UI) / 5031 (peer) | NodePort 30030 / 30031 |
| Autobrr | `ghcr.io/autobrr/autobrr` | 7474 | 10.0.1.5 |
| Qui | `ghcr.io/autobrr/qui` | 7476 | 10.0.1.13 |
| Upbrr | `ghcr.io/autobrr/upbrr` ([private-tracker upload prep](https://github.com/autobrr/upbrr)) | 7480 | 10.0.1.17 |
| Q1 | `linuxserver/qbittorrent` | 8080 (webui) / 31081 (torrent) | 10.0.1.10 (torrent → NodePort 31081) |
| Q2 | `linuxserver/qbittorrent` | 8080 (webui) / 31082 (torrent) | 10.0.1.11 (torrent → NodePort 31082) |
| Q3 | `linuxserver/qbittorrent` | 8080 (webui) / 31083 (torrent) | 10.0.1.12 (torrent → NodePort 31083) |
| Jellyfin | `linuxserver/jellyfin` | 8096 | 10.0.1.7 |
| Bazarr | `linuxserver/bazarr` | 6767 | 10.0.1.6 |
| SFTPGo | `drakkan/sftpgo` | 2022/8080 | NodePort 32022 / 30883 (webdav → LB 10.0.1.18 :80) |
| Profilarr | `ghcr.io/dictionarry-hub/profilarr` ([quality profile manager](https://github.com/Dictionarry-Hub/profilarr)) | 6868 | 10.0.1.19 |

Infra: Argo CD `10.0.1.3` (:80/443), Homepage `10.0.1.4` (:80), Gateway `10.0.1.2` (:80/443), SFTPGo webdav `10.0.1.18` (:80), AdGuard `10.0.1.20` (DNS :53, UI :80).

## Removing an App

> **GitOps removal: commit → push → Argo CD prunes automatically.**

1. Delete `apps/<category>/<name>/`.
2. Remove its PV/PVC entry from `apps/infra/storage/values.yaml`.
3. If it has a Tailscale ingress, remove the entry from `apps/infra/tailscale/values.yaml`.
4. If it appears in the Homepage dashboard, remove it from `apps/infra/homepage/values.yaml`.
5. Validate, commit, and push:
   ```bash
   helm template apps/infra/storage
   helm template apps/infra/tailscale
   git commit -am "remove <name>"
   git push
   ```
6. Log in to the Argo CD CLI (one-liner — run once per session):
   ```bash
   argocd login localhost --insecure --grpc-web --port-forward --port-forward-namespace infra \
     --username admin \
     --password "$(kubectl -n infra get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
   ```

7. **Wait** — do not stop here. Poll until every affected app is done:
   ```bash
   # Wait for the app's Application object to be pruned (disappear completely)
   until ! argocd app get media-<name> --grpc-web --port-forward --port-forward-namespace infra &>/dev/null; do
     echo "$(date '+%H:%M:%S') media-<name> still exists, sleeping 15s..."; sleep 15
   done
   echo "pruned"

   # Wait for infra-storage to reconcile to the new commit and prune the PV/PVC
   until argocd app get infra-storage --grpc-web --port-forward --port-forward-namespace infra 2>/dev/null \
     | grep -q "<commit-sha>"; do
     echo "$(date '+%H:%M:%S') infra-storage on old commit, sleeping 15s..."; sleep 15
   done
   argocd app wait infra-storage --sync --health --grpc-web --port-forward --port-forward-namespace infra

   # Wait for the tailscale ingress to be pruned
   argocd app wait infra-tailscale --sync --health --grpc-web --port-forward --port-forward-namespace infra
   ```

> **Do not manually delete Kubernetes resources — push to git and let Argo CD prune. That's the point.**

## Deploying a New App

1. Create `apps/<category>/<name>/` as a Helm chart.
2. Add its PV/PVC to `apps/infra/storage/values.yaml` before the app deploys.
3. Add `templates/httproute.yaml` (Gateway API DDNS) and `templates/ingress-tailscale.yaml` (VPN mesh).
4. Commit and push — Argo CD detects and deploys automatically.

**Step 1 — validate before pushing (required):**
```bash
helm template apps/<category>/<app>
```

**Step 2 — log in to the Argo CD CLI (once per session):**
```bash
argocd login localhost --insecure --grpc-web --port-forward --port-forward-namespace infra \
  --username admin \
  --password "$(kubectl -n infra get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
```

**Step 3 — after pushing, wait until Synced + Healthy (required). Do not stop here — actually run these and wait:**

Argo CD polls git every ~3 minutes. Do not call the task done at "pushed" — block until the app reports green and the pod is Running. If either stalls, dig into events/logs before moving on.

```bash
# Block until the Application is Synced + Healthy
argocd app wait <category>-<name> --sync --health --grpc-web --port-forward --port-forward-namespace infra

# Watch the pod come up
kubectl get pod -n <namespace> -l app.kubernetes.io/name=<name> -w

# If something is wrong
kubectl describe application -n infra <category>-<name>
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name>
```

> Do not manually trigger `argocd app sync` — push to git and let Argo CD reconcile. That's the point.

## Troubleshooting

### Other issues

| Problem | Fix |
|---|---|
| Argo CD sync stuck on large CRDs | `ServerSideApply=true` is set in the ApplicationSet; check `repo-server` memory (≥ `512Mi`) |
| App can't write to config dir | Ensure `securityContext.runAsUser: 1000` and add a root `initContainer` that `chown -R 1000:1000`s the config mount (hostPath dirs are created `root:root`) |
| Non-LinuxServer image running as root | `PUID`/`PGID` env vars are silently ignored; use `securityContext` instead |
| Qui first-run setup | `config.toml` is auto-generated by an initContainer; after first deploy, exec into the running pod and run `qui create-user` |
| Cert not issued / HTTPS handshake fails | Check `apps/infra/lego`'s CronJob logs and the `*-tls` Secrets in `infra`; then confirm the Gateway's listener `certificateRefs` matches and `kubectl get httproute -A` shows `ResolvedRefs=True` |
| Tailscale ingress for HTTPS service | Backend port must be `443`, not the app's HTTP port |

## Known Issues & Improvements

### Critical

**Old credentials remain in git history**
Secrets now live only in OpenBao and are synced by External Secrets, but the DDNS, Tailscale and slskd values were committed in plaintext base64 before the migration and are still reachable through GitHub's retained refs. Rotate them at each provider and write the new values to OpenBao (`secret/homelab/*`).

### High

**Sonarr chart drift**
`apps/media/sonarr` is a local chart like every other media app (its
`Chart.yaml` has no upstream dependency), and its LoadBalancer IP is now set
explicitly in `values.yaml`. Keep it consistent with the rest of the stack.

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

### Low

**Homepage dashboard links are hardcoded**
`apps/infra/homepage/values.yaml` hardcodes all service URLs. Adding a new app requires manually updating this config — it won't auto-discover new Argo CD applications.
