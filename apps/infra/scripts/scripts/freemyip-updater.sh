#!/bin/sh
set -ex
curl "https://freemyip.com/update?token=${FREEMYIP_TOKEN}&domain={{ index .Values.jobs "freemyip-updater" "domain" }}"
