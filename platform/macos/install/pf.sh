#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

pf_anchor=pi-sandbox-macos
sudo sed -i '' '/happ-local/d' /etc/pf.conf
sudo rm -f /etc/pf.anchors/happ-local
sudo sed -i '' -e '/anchor "pi-sandbox"$/d' -e '/\/pf\.anchors\/pi-sandbox"$/d' /etc/pf.conf
sudo rm -f /etc/pf.anchors/pi-sandbox
sudo cp "${SBX}/platform/macos/pf/${pf_anchor}" "/etc/pf.anchors/${pf_anchor}"
if ! grep -q "${pf_anchor}" /etc/pf.conf; then
  printf 'anchor "%s"\nload anchor "%s" from "/etc/pf.anchors/%s"\n' "${pf_anchor}" "${pf_anchor}" "${pf_anchor}" \
    | sudo tee -a /etc/pf.conf >/dev/null
fi
sudo pfctl -f /etc/pf.conf || { echo "install: pf ruleset не загрузился" >&2; exit 1; }
sudo pfctl -E >/dev/null 2>&1 || { echo "install: pf enable failed" >&2; exit 1; }

