#!/bin/sh
# Prometheus metrics for every mounted bcachefs filesystem, read straight from
# the kernel's sysfs (/sys/fs/bcachefs) so they never depend on a matching
# bcachefs-tools version. Rewritten every $INTERVAL seconds and served by
# busybox httpd on :$PORT/metrics. Pool-level size/used/avail come from
# node-exporter (statfs); this adds what only bcachefs knows.
set -eu
PORT=${PORT:-9101}
INTERVAL=${INTERVAL:-30}
www=/tmp/www
mkdir -p "$www"
httpd -p "$PORT" -h "$www"

# Counters (events since mount) worth graphing; see /sys/fs/bcachefs/*/counters.
COUNTERS="copygc data_read data_write data_update bucket_alloc_fail bucket_discard evacuate_bucket journal_full journal_reclaim_start error_throw data_read_retry"

collect() {
  for fs in /sys/fs/bcachefs/*-*; do
    [ -d "$fs" ] || continue
    uuid=$(basename "$fs")
    echo "bcachefs_btree_cache_bytes{fs=\"$uuid\"} $(tobytes "$(cat "$fs/btree_cache_size")")"
    echo "bcachefs_reconcile_scan_pending{fs=\"$uuid\"} $(head -n 1 "$fs/reconcile_scan_pending")"
    # errors: "<name> <count> <first> <last>" per error type ever seen.
    awk -v fs="$uuid" 'NF >= 2 { printf "bcachefs_errors_total{fs=\"%s\",error=\"%s\"} %s\n", fs, $1, $2 }' "$fs/errors"
    for c in $COUNTERS; do
      [ -e "$fs/counters/$c" ] || continue
      awk -v fs="$uuid" -v c="$c" '/since mount/ { printf "bcachefs_counter_total{fs=\"%s\",counter=\"%s\"} %s\n", fs, c, $NF }' "$fs/counters/$c"
    done
    for d in "$fs"/dev-*; do
      dev=${d##*/dev-}
      label=$(cat "$d/label")
      path=$(readlink "$d/block") # .../block/<disk>/<partition>
      blk=$(basename "$path")
      disk=$(basename "$(dirname "$path")")
      # bcachefs's own dev-N/rotational is not reliable; ask the block layer.
      rot=$(cat "/sys/block/$disk/queue/rotational" 2>/dev/null || cat "/sys/block/$blk/queue/rotational")
      state=$(sed -n 's/.*\[\([a-z]*\)\].*/\1/p' "$d/state")
      l="fs=\"$uuid\",dev=\"$dev\",label=\"$label\",device=\"$blk\""
      echo "bcachefs_device_info{$l,state=\"$state\",rotational=\"$rot\"} 1"
      for s in rw ro evacuating spare; do
        echo "bcachefs_device_state{$l,state=\"$s\"} $([ "$s" = "$state" ] && echo 1 || echo 0)"
      done
      echo "bcachefs_device_durability{$l} $(cat "$d/durability")"
      bucket=$(tobytes "$(cat "$d/bucket_size")")
      # alloc_debug: "<type> <buckets> <sectors> <fragmented>" rows, then
      # "capacity <buckets>".
      awk -v l="$l" -v b="$bucket" '
        $1 == "capacity" { printf "bcachefs_device_capacity_bytes{%s} %.0f\n", l, $2 * b }
        $1 == "free" && NF == 4 { printf "bcachefs_device_free_bytes{%s} %.0f\n", l, $2 * b }
        NF == 4 && $2 ~ /^[0-9]+$/ && $1 != "free" {
          printf "bcachefs_device_data_bytes{%s,type=\"%s\"} %.0f\n", l, $1, $3 * 512
          printf "bcachefs_device_fragmented_bytes{%s,type=\"%s\"} %.0f\n", l, $1, $4 * 512
        }
        /^reserves:/ { exit }' "$d/alloc_debug"
      # io_errors: first block is "since filesystem creation".
      awk -F: -v l="$l" '/since filesystem creation/ { on = 1; next } /since/ { on = 0 }
        on && NF == 2 { gsub(/ /, "", $1); gsub(/ /, "", $2)
          printf "bcachefs_device_io_errors_total{%s,type=\"%s\"} %s\n", l, $1, $2 }' "$d/io_errors"
    done
  done
}

# Pool-wide accounting that sysfs does not expose (replicas, erasure coding,
# pending reconcile), parsed from `bcachefs fs usage` on $USAGE_PATH, a path
# inside the filesystem. Needs bcachefs-tools close to the kernel's version.
# Sections and rows that are zero are omitted by the tool.
usage() {
  [ -n "${USAGE_PATH:-}" ] || return 0
  bcachefs fs usage "$USAGE_PATH" | awk '
    function out(name, labels, v) { printf "bcachefs_%s{fs=\"%s\"%s} %s\n", name, fs, labels, v }
    /^Filesystem:/ { fs = $2 }
    /^Size:/ { out("size_bytes", "", $2) }
    /^Used:/ { out("used_bytes", "", $2) }
    /^Online reserved:/ { out("online_reserved_bytes", "", $3) }
    /^Replicated:/ { sec = "rep"; getline; n = split($0, col); next }
    /^Erasure coded/ { sec = "ec"; getline; n = split($0, col); next }
    /^Pending reconcile:/ { sec = "pend"; sub(/^[^:]*:/, ""); n = split($0, col); next }
    /^Data type|^Device label/ { sec = "" }
    /^[[:space:]]*$/ { sec = ""; next }
    /^cached:/ && NF == 2 { out("cached_bytes", "", $2) }
    /^reserved:/ && NF == 2 { out("reserved_bytes", "", $2) }
    sec == "rep" && $1 ~ /^[0-9]+x:$/ {
      r = $1; sub(/x:/, "", r)
      for (i = 2; i <= NF; i++) out("replicated_bytes", ",replicas=\"" r "\",state=\"" col[i-1] "\"", $i) }
    sec == "ec" && $1 ~ /^[0-9]+\+[0-9]+:$/ {
      s = $1; sub(/:/, "", s); split(s, p, "+")
      for (i = 2; i <= NF; i++)
        out("erasure_coded_bytes", ",scheme=\"" s "\",data=\"" p[1] "\",parity=\"" p[2] "\",state=\"" col[i-1] "\"", $i) }
    sec == "pend" && $1 ~ /:$/ {
      w = $1; sub(/:/, "", w)
      for (i = 2; i <= NF; i++) out("reconcile_pending_bytes", ",reason=\"" w "\",type=\"" col[i-1] "\"", $i) }'
  echo "bcachefs_tools_info{version=\"$(bcachefs version)\"} 1"
}

# "1.92G" -> bytes (sysfs prints human sizes with binary suffixes).
tobytes() {
  echo "$1" | awk '{ v = $1; m = 1; u = substr(v, length(v))
    if (u ~ /[kKMGTP]/) { v = substr(v, 1, length(v) - 1); m = 1024 ^ index("KMGTP", toupper(u)) }
    printf "%.0f", v * m }'
}

while :; do
  if { collect; usage; } > "$www/metrics.tmp" 2> "$www/error"; then
    mv "$www/metrics.tmp" "$www/metrics"
  else
    cat "$www/error" >&2
  fi
  sleep "$INTERVAL"
done
