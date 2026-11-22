# Backup

Weekly encrypted offsite backup of `hostRoot`/`paths` (today `/data/tier1` and
`/data/tier2`) to the Cloudflare R2 bucket `homelab-backup`, kept strictly
inside the R2 free tier. How the guards work is described at the top of
[`scripts/backup.sh`](scripts/backup.sh); the limits are in `values.yaml`.

Each run snapshots the paths read-only (bcachefs), packs them into one
`homelab-<YYYYMMDD>.tar.zst.age` encrypted to the SSH public keys in
`values.yaml`, uploads it, then writes a `.ok` marker holding its sha256 and size.
Only archives with a marker count; at most `keep` are kept.

## Setup (done once)

- Bucket `homelab-backup` (location APAC, storage class Standard, a 1-day
  abort-multipart lifecycle rule), created with `wrangler`.
- An R2 API token scoped to that bucket (Object Read & Write), stored in
  OpenBao at `secret/homelab/r2-backup` with keys `ACCESS_KEY_ID`,
  `SECRET_ACCESS_KEY`, `ENDPOINT` and `BUCKET`. `apps/infra/secrets` syncs it
  into Secret `r2-backup-secret`.

## Run now

```sh
kubectl -n infra create job --from=cronjob/r2-backup r2-backup-now
kubectl -n infra logs -f job/r2-backup-now
```

## Restore

Decrypting needs one of the SSH private keys whose public key is in
`values.yaml`. The restore extracts over `hostRoot`, so stop the affected apps
first.

```sh
kubectl -n infra create secret generic r2-restore-identity --from-file=identity=$HOME/.ssh/id_ed25519
kubectl -n infra create job --from=cronjob/r2-restore r2-restore-now   # newest archive
kubectl -n infra logs -f job/r2-restore-now
kubectl -n infra delete secret r2-restore-identity
```

For a specific date, edit `SNAPSHOT` (`YYYYMMDD`) in the Job before it starts,
or run it by hand. Without the cluster, on any machine with `rclone`, `age`,
`zstd` and `tar`:

```sh
rclone cat r2:homelab-backup/homelab-<date>.tar.zst.age \
  | age -d -i ~/.ssh/id_ed25519 | zstd -d | tar -C /data -xf -
```
