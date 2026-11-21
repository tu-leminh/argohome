# OpenBao

Argo deploys this chart as `infra-openbao`: the upstream `openbao` chart,
standalone, one replica, `pebbledb` storage on the static tier1 PV
`infra-openbao-tier1-data` (`/data/tier1/openbao/data`, defined in
`apps/infra/storage`). No ingress: reach the UI with
`kubectl -n infra port-forward svc/infra-openbao 8200`.

Ownership of the data directory is fixed by a root `chown-data` initContainer
(hostPath dirs are created `root:root`); no host prep is needed.

## Bootstrap (nothing to do)

OpenBao bootstraps itself, with no host or manual steps:

- The `chown-data` initContainer generates the static-seal key
  `/data/tier1/openbao/data/unseal.key` (32 raw bytes) if it is missing, and
  never overwrites it.
- On its very first start OpenBao runs the `initialize` blocks in `values.yaml`
  (declarative self-init), and on every restart it unseals itself with that key.

The key sits next to the data on tier1, so the weekly Drive backup of tier1
covers both. Without the key the data cannot be decrypted, so keep that backup
(and, if you want, a separate offline copy of `unseal.key`).

Self-init creates: a KV v2 mount at `secret/`, the `kubernetes` auth method,
the read-only `eso-read` policy/role used by External Secrets, and an `admin`
policy/role. The root token is revoked and no recovery keys exist.

## Admin access

```sh
jwt=$(kubectl -n infra create token openbao-admin)
kubectl -n infra exec -i infra-openbao-0 -c openbao -- \
  env BAO_ADDR=http://127.0.0.1:8200 bao write -field=token auth/kubernetes/login role=admin jwt="$jwt"
```

Use the printed token as `BAO_TOKEN` (valid 1 hour). Anyone who can mint a token
for `openbao-admin` is an OpenBao admin, which is no more than cluster access
already allows.

## Changing the config later

Self-init runs only once. Make later changes through an authenticated `admin`
login (or an Argo-managed Job), or wipe `/data/tier1/openbao/data` and restart
to re-initialize from scratch (only safe while OpenBao holds nothing you need;
remove only the `pebbledb` directory and keep `unseal.key`, or delete both and let
the initContainer make a fresh key).
Changing the `initialize` blocks of an already-initialized instance has no
effect.

## Stored secrets

| Path | Synced to | By |
|---|---|---|
| `secret/homelab/duckdns` | `infra/duckdns-secret` | `apps/infra/secrets` |
| `secret/homelab/freemyip` | `infra/freemyip-secret` | `apps/infra/secrets` |
| `secret/homelab/myaddr` | `infra/myaddr-secret` | `apps/infra/secrets` |
| `secret/homelab/tailscale` | `infra/tailscale-secret` | `apps/infra/secrets` |
| `secret/homelab/slskd` | `media/media-slskd-secret` | `apps/media/slskd` |

To add or rotate one, log in as `admin` (above) and
`bao kv put -mount=secret homelab/<name> KEY=value ...` (or pipe JSON to `-`
so values stay out of your shell history). External Secrets re-syncs hourly.
