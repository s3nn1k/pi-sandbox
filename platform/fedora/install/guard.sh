#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

sudo install -Dm 644 "${SBX}/platform/fedora/nft/pi-sandbox-guard.nft" /etc/pi-sandbox/guard.nft
sudo install -m 644 "${SBX}/platform/fedora/systemd/system/pi-sandbox-guard.service" /etc/systemd/system/pi-sandbox-guard.service
sudo systemctl daemon-reload
sudo systemctl enable pi-sandbox-guard
sudo systemctl restart pi-sandbox-guard
systemctl is-active --quiet pi-sandbox-guard \
  || { echo "install: юнит pi-sandbox-guard не активен (journalctl -u pi-sandbox-guard)" >&2; exit 1; }
guard_table="$(sudo nft list table inet pi_sandbox_guard 2>/dev/null || true)"
if ! { grep -q prerouting_guard <<<"$guard_table" \
       && grep -qF 'fib daddr type local' <<<"$guard_table" \
       && grep -qF 'priority dstnat - 10' <<<"$guard_table"; }; then
  echo "install: в nft-таблице pi_sandbox_guard нет prerouting_guard / fib daddr type local / priority dstnat - 10" >&2
  exit 1
fi
[ -f /run/pi-sandbox-guard.active ] \
  || { echo "install: нет штампа /run/pi-sandbox-guard.active" >&2; exit 1; }
