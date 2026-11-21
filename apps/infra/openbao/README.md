# OpenBao

Argo deploys this chart as `infra-openbao`: the upstream `openbao` chart,
standalone, one replica, `pebbledb` storage on the static tier1 PV
`infra-openbao-tier1-data` (`/data/tier1/openbao/data`, defined in
`apps/infra/storage`). No ingress: reach the UI with
`kubectl -n infra port-forward svc/infra-openbao 8200`.

Ownership of the data directory is fixed by a root `chown-data` initContainer
(hostPath dirs are created `root:root`); no host prep is needed.

## Init and unseal (once, manual)

```sh
kubectl -n infra exec openbao-0 -- bao operator init -key-shares=1 -key-threshold=1
kubectl -n infra exec openbao-0 -- bao operator unseal
```

Store the unseal key and root token outside the cluster and outside
Vaultwarden. OpenBao seals again on every pod restart and must be unsealed
by hand (no auto-unseal configured).

## Not yet done

Nothing consumes OpenBao yet. `apps/infra/secrets` still holds the plaintext
base64 Secrets. Follow-up: load them into a KV v2 mount, sync them into
Kubernetes (e.g. External Secrets Operator), then delete that chart.
