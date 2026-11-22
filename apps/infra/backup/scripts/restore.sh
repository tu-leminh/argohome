#!/bin/sh
# Restore an R2 archive over $HOST_ROOT/<paths>. $SNAPSHOT is a date
# (YYYYMMDD) or "latest" (newest archive with a .ok marker). Decrypting needs
# one of the owner's SSH private keys, mounted from Secret r2-restore-identity
# only for the restore (see ../README.md). A download is a few Class B ops.
set -eu
: "${HOST_ROOT:?}" "${BUCKET:?}" "${SNAPSHOT:?}"
remote="r2:$BUCKET"
listing=$(rclone lsf --files-only "$remote/")
if [ "$SNAPSHOT" = latest ]; then
  name=$(echo "$listing" | grep '\.age\.ok$' | sort | tail -n 1 | sed 's/\.ok$//')
else
  name="homelab-$SNAPSHOT.tar.zst.age"
  echo "$listing" | grep -qx "$name.ok" || name=""
fi
[ -n "$name" ] || { echo "no complete archive found" >&2; exit 1; }
rclone cat "$remote/$name" | age -d -i /etc/r2-restore/identity | zstd -dq | tar -C "$HOST_ROOT" -xf -
echo "restored $name into $HOST_ROOT"
