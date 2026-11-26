#!/usr/bin/env bash
set -euo pipefail

systemctl is-enabled --quiet docker \
  || { echo "install: docker не в автозапуске — sudo systemctl enable --now docker" >&2; exit 1; }
docker info >/dev/null 2>&1 \
  || { echo "install: docker недоступен (группа docker / re-login?)" >&2; exit 1; }
