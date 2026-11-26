#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

mkdir -p "${HOME}/.config/systemd/user"
install -m 644 "${SBX}/platform/fedora/systemd/user/herdr-bridge.service" "${HOME}/.config/systemd/user/herdr-bridge.service"
systemctl --user daemon-reload
systemctl --user enable --now herdr-bridge
systemctl --user try-restart herdr-bridge
