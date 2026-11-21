# OpenBao

Argo deploys this chart as `infra-openbao`: the upstream `openbao` chart,
standalone, one replica, `pebbledb` storage on the static tier1 PV
`infra-openbao-tier1-data` (`/data/tier1/openbao/data`, defined in
`apps/infra/storage`). No ingress: reach the UI with
`kubectl -n infra port-forward svc/infra-openbao 8200`.

Ownership of the data directory is fixed by a root `chown-data` initContainer
(hostPath dirs are created `root:root`); no host prep is needed.

## Bootstrap (once, per cluster)

OpenBao initializes itself from the `initialize` blocks in `values.yaml` on its
very first start (declarative self-init) and unseals itself on every restart
(static seal). The only thing you provide is the seal key, **before** the pod
first starts:

```sh
openssl rand -out unseal.key 32                      # exactly 32 raw bytes
kubectl -n infra create secret generic openbao-unseal-key --from-file=key=unseal.key
```

Keep `unseal.key` somewhere safe and **outside the cluster**: without it the
data in `/data/tier1/openbao/data` cannot be decrypted. (The nix flake seeds
this Secret from `/data/tier1/openbao/bootstrap/unseal.key` on its host; that is
optional automation of the two commands above.)

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
to re-initialize from scratch (only safe while OpenBao holds nothing you need).
Changing the `initialize` blocks of an already-initialized instance has no
effect.

## Not yet done

`apps/infra/secrets` still holds the plaintext base64 Secrets. The follow-up
is to load them into the KV mount under `secret/homelab/`, sync them with
External Secrets (`apps/infra/external-secrets`), then delete that chart.
