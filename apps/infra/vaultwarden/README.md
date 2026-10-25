# Vaultwarden

Argo deploys this chart as `infra-vaultwarden`. One replica uses SQLite under
`/data/tier2/configs/vaultwarden`; the PV's default reclaim policy is Retain.
The image and backup image are pinned by digest. The container runs as UID 1000.

Canonical URL: https://vault.epricesx.duckdns.org . FreeMyIP is an alternate
entry point. Tailscale uses `vault` with no public Funnel. MyAddr is disabled
until its separate hostname credential and certificate are provisioned.
Use the canonical URL for Bitwarden clients and account links.

## First account

Public registration and organization invitations are disabled. Open `/admin`
and obtain the admin password locally with:

```sh
sudo cat /data/bootstrap/vaultwarden/admin-token.txt
```

Invite your email from the admin page, then register using exactly that email.
SMTP is not configured, so no invitation email is sent. The admin token is
separate from your vault master password. Enable account MFA and keep recovery
codes outside this server. Do not save application settings through the admin
page: `config.json` overrides Git-managed environment configuration.

The Argon2 hash is in `/data/bootstrap/vaultwarden/admin.env`, mounted read-only
through ENV_FILE. Both credential files stay outside Git. This intentionally
avoids requiring the still-unprovisioned Argo SOPS key to recover this app.
The parent is root:1000 mode 0750; admin.env is root:1000 mode 0640; the original
token is root-only mode 0600. Back up these files separately and securely.

## Backups and restore

A CronJob runs at 02:17 Asia/Ho_Chi_Minh, retaining 14 successful archives under
`/data/backups/vaultwarden`. It uses SQLite's online backup API and checks database
integrity before atomically publishing an archive, including attachments, sends,
and signing keys. Attachment copies are not transactionally coordinated with DB
writes; avoid modifying attachments during backups. This is a local backup,
not protection against loss of the host disks. No remote destination is configured.

For a cluster rebuild with intact `/data`, restore host configuration and the
GitOps bootstrap; existing data and credentials are reused. Never initialize a
new database over the old directory. If restoring an archive, stop Vaultwarden,
extract into an empty data directory (do not retain an old WAL/SHM), restore UID
1000 ownership and restricted permissions, then restart. Preserve the current
data directory until the restored instance is verified. Restore the admin.env
file separately. Test restores using a copy and an isolated instance, never the
live database. Keep SOPS age keys and bootstrap credentials outside Vaultwarden
so recovery does not depend on starting the vault first.
