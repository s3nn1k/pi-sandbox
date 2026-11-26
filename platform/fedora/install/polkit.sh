#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

sudo install -Dm 644 "${SBX}/platform/fedora/polkit/49-pi-sandbox-firewalld-inspect.rules" \
  /etc/polkit-1/rules.d/49-pi-sandbox-firewalld-inspect.rules
