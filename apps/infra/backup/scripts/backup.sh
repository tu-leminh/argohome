#!/bin/sh
# Weekly offsite backup to Cloudflare R2, kept strictly inside the free tier.
# R2 bills overage with no hard cap of its own, so the guards live here:
#   storage  one archive per run, at most $KEEP kept, and the bucket total must
#            stay <= $HARD_CAP before the upload (else nothing is uploaded and
#            the existing backups are kept) and after it (else the new archive
#            is removed); above $WARN_AT the run fails so someone notices
#   Class A  (writes and lists, 1M/month free) one object per run in
#            $CHUNK_MIB MiB multipart parts, a few lists, and a local monthly
#            budget ($CLASS_A_BUDGET) that stops runs long before the limit;
#            deletes are free on R2
#   Class B  (reads, 10M/month free) the backup never reads objects back
# Sources are read-only bcachefs snapshots (consistent SQLite/pebbledb state),
# archived as one tar.zst and encrypted with age to the owner's SSH keys.
set -eu
: "${HOST_ROOT:?}" "${PATHS:?}" "${BUCKET:?}"
remote="r2:$BUCKET"
state="$HOST_ROOT/.r2-backup"
snapdir="$state/snap"
name="homelab-$(date +%Y%m%d).tar.zst.age"
chunk=$((CHUNK_MIB * 1048576))
mkdir -p "$state"
rm -f "$state"/*.age

# Local tally of the Class A operations this job makes, per calendar month.
opsfile="$state/class-a-$(date +%Y%m)"
used=$(cat "$opsfile" 2>/dev/null || echo 0)
ops() { used=$((used + $1)); echo "$used" > "$opsfile"; }
if [ "$used" -ge "$CLASS_A_BUDGET" ]; then
  echo "monthly Class A budget used up ($used ops); not uploading" >&2; exit 1
fi

cleanup_snaps() {
  for p in $PATHS; do
    if [ -e "$snapdir/$p" ]; then bcachefs subvolume delete "$snapdir/$p"; fi
  done
}
trap 'cleanup_snaps; rm -f "$state"/*.age' EXIT
cleanup_snaps # leftovers from an interrupted run
for p in $PATHS; do
  mkdir -p "$(dirname "$snapdir/$p")"
  bcachefs subvolume snapshot -r "$HOST_ROOT/$p" "$snapdir/$p"
done
# shellcheck disable=SC2086 # PATHS is a word list
tar -C "$snapdir" -cf - $PATHS | zstd -q -T0 -10 | age -R /etc/r2-backup/recipients > "$state/$name"
cleanup_snaps
size=$(stat -c %s "$state/$name")
sha=$(sha256sum "$state/$name" | cut -d' ' -f1)
echo "archive $name: $size bytes"
if [ "$size" -gt "$HARD_CAP" ]; then
  echo "archive alone exceeds the cap; not uploading" >&2; exit 1
fi

# One LIST. An archive counts only with its .ok marker, which is written last;
# anything else is a failed run and is deleted (free).
ops 1
listing=$(rclone lsf --files-only --format sp --separator ' ' "$remote/")
good=""
for f in $(echo "$listing" | cut -d' ' -f2 | grep '\.age$' | sort); do
  if echo "$listing" | grep -qx "[0-9]* $f.ok"; then good="$good $f"; else rclone deletefile "$remote/$f"; fi
done
for m in $(echo "$listing" | cut -d' ' -f2 | grep '\.ok$'); do
  echo "$good" | grep -qw "${m%.ok}" || rclone deletefile "$remote/$m"
done
# Keep KEEP-1 old archives so that KEEP remain after this upload.
n=$(echo "$good" | wc -w)
drop=$((n - KEEP + 1))
# shellcheck disable=SC2086 # $good is a word list
for f in $(printf '%s\n' $good | head -n "$((drop > 0 ? drop : 0))"); do
  rclone deletefile "$remote/$f"; rclone deletefile "$remote/$f.ok"
  good=$(echo "$good" | sed "s/ $f//")
done
total=0
for f in $good; do
  total=$((total + $(echo "$listing" | grep " $f$" | cut -d' ' -f1)))
done
if [ $((total + size)) -gt "$HARD_CAP" ]; then
  echo "bucket would reach $((total + size)) bytes (> cap); not uploading" >&2; exit 1
fi

# Multipart upload: create + complete + one op per part.
ops $(( (size + chunk - 1) / chunk + 2 ))
rclone copyto --s3-upload-cutoff "${CHUNK_MIB}Mi" --s3-chunk-size "${CHUNK_MIB}Mi" "$state/$name" "$remote/$name"
ops 1
echo "$sha $size" | rclone rcat "$remote/$name.ok"

# Re-check the real bucket total (one more LIST); undo if over the cap.
ops 1
now=$(rclone size --json "$remote/" | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
echo "bucket total: $now bytes; Class A ops this month: $used"
if [ "$now" -gt "$HARD_CAP" ]; then
  rclone deletefile "$remote/$name.ok"; rclone deletefile "$remote/$name"
  echo "bucket over the cap after upload; removed the new archive" >&2; exit 1
fi
if [ "$now" -gt "$WARN_AT" ]; then
  echo "WARNING: bucket at $now bytes, close to the free tier" >&2; exit 1
fi
