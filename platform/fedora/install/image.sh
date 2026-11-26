#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

make -C "${SBX}" image \
  || echo "install: WARN: make image не прошёл — догони вручную: make -C ${SBX} image" >&2
make -C "${SBX}" seeds \
  || echo "install: WARN: seeds не прошли — повтори: make -C ${SBX} seeds" >&2
