#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

live_sess="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-' || true)"
make -C "${SBX}" image \
  || echo "install: WARN: make image не прошёл — догони вручную: make -C ${SBX} image" >&2
if [ "${live_sess}" = 0 ] 2>/dev/null; then
  make -C "${SBX}" seeds \
    || echo "install: WARN: seeds не прошли — повтори: make -C ${SBX} seeds" >&2
fi
