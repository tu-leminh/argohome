# SOPS age key setup and recovery

Run once per cluster; normal reboots and Git pushes need no manual setup.
Keep the private key outside Git. Argo CD reads `infra/sops-age-key`, field
`keys.txt`, mounted at `/helm-secrets-private-keys/keys.txt`.

## Key and independent backup

Use a trusted workstation with `age`, `sops`, and `kubectl`. For a new installation:

```bash
umask 077
SOPS_KEY_PATH="$HOME/.config/sops/age/keys.txt"
mkdir -p "$(dirname "$SOPS_KEY_PATH")"
age-keygen -o "$SOPS_KEY_PATH"
age-keygen -y "$SOPS_KEY_PATH"
```

Put the printed public recipient in [`.sops.yaml`](../.sops.yaml). If encrypted
values already exist, restore their matching private key instead of generating one.
Back up to external storage accessible without this cluster or its S3 service:

```bash
BACKUP_FILE=/media/offline-backup/argohome-sops-age-keys.txt.age
age --passphrase --output "$BACKUP_FILE" "$SOPS_KEY_PATH"
```

Record the backup location and keep its passphrase in an independent password
manager. Test restoration before disconnecting the drive; never commit the key.

## Restore and verify

Set `BACKUP_FILE` to the recorded backup location and choose an unused output path:

```bash
umask 077
SOPS_KEY_PATH="$HOME/.config/sops/age/restored-keys.txt"
mkdir -p "$(dirname "$SOPS_KEY_PATH")"
age --decrypt --output "$SOPS_KEY_PATH" "$BACKUP_FILE"
age-keygen -y "$SOPS_KEY_PATH" # Must match .sops.yaml.
```

From the repository root, check decryption without displaying plaintext:

```bash
set -o pipefail
printf 'check: ok\n' | sops encrypt --filename-override secrets.sops.yaml |
  SOPS_AGE_KEY_FILE="$SOPS_KEY_PATH" sops decrypt --input-type yaml --output-type yaml > /dev/null
```

## Provision the cluster

Confirm `kubectl config current-context`. This is the GitOps bootstrap/recovery
exception; run it for initial setup and after rebuilding the cluster:

```bash
set -o pipefail
kubectl create namespace infra --dry-run=client -o yaml | kubectl apply -f -
kubectl -n infra create secret generic sops-age-key \
  --from-file=keys.txt="$SOPS_KEY_PATH" --dry-run=client -o yaml |
  kubectl apply --server-side --field-manager=sops-age-bootstrap -f -
# After the Argo CD configuration is merged into main and the Deployment exists:
kubectl -n infra rollout restart deployment/infra-argocd-repo-server
kubectl -n infra rollout status deployment/infra-argocd-repo-server --timeout=180s
```

Verify an application configured to use encrypted values becomes `Synced` and
`Healthy`. The optional key mount means pod health alone does not prove decryption.
Application encrypted-values wiring is separate. A replacement key cannot decrypt
old ciphertext; retain matching keys for retained Git revisions.
