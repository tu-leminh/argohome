#!/bin/sh
set -ex
curl -X POST "https://myaddr.tools/update?key=${MYADDR_KEY}&ip=self"
