#!/bin/sh
set -ex
echo url="https://www.duckdns.org/update?domains={{ index .Values.jobs "duckdns-updater" "domain" }}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o /dev/null -K -
