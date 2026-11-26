#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"
# shellcheck source=/dev/null
. "${SBX}/platform/macos/lib.sh"

if ! colima status >/dev/null 2>&1; then
  colima start --vm-type vz --mount-type virtiofs --cpu 4 --memory 10
fi
brew services start colima >/dev/null 2>&1 || true

cfg="${HOME}/.colima/default/colima.yaml"
cfg_before="$(md5 -q "${cfg}" 2>/dev/null || echo none)"
"${SBX}/platform/macos/sandbox-sync"
ln -sfn "${SBX}/platform/macos/sandbox-sync" "${HOME}/.local/bin/sandbox-sync"
cfg_changed=0
[ "$(md5 -q "${cfg}" 2>/dev/null || echo none)" != "${cfg_before}" ] && cfg_changed=1

if [ "${cfg_changed}" = 1 ]; then
  live_sess="$(DOCKER_CONTEXT=colima docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-' || true)"
  if [ "${live_sess:-0}" -gt 0 ]; then
    echo "install: ${live_sess:-0} живых агент-сессий — рестарт VM оборвёт их. Останови pi или ре-ран позже." >&2
    exit 1
  fi
  echo "install: colima.yaml изменился — применяю рестартом VM"
  colima restart >/dev/null
else
  echo "install: конфиг VM без изменений — рестарт не нужен"
fi
vm_firewall_rules_present \
  || { echo "install: firewall неполный (нет EST/4761/DROP или весь отсутствует)" >&2; exit 1; }
