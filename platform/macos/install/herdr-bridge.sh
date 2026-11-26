#!/usr/bin/env bash
set -euo pipefail
SBX="${HOME}/pi-sandbox"

mkdir -p "${HOME}/Library/Logs/pi-sandbox-macos" "${HOME}/.local/bin" "${HOME}/Library/LaunchAgents"
ln -sfn "${SBX}/platform/macos/herdr-sock-bridge" "${HOME}/.local/bin/herdr-sock-bridge"
launchctl bootout "gui/$(id -u)/com.s3nn1k.herdr-bridge" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/com.pi-sandbox.herdr-bridge" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/com.pi-sandbox-macos.herdr-bridge" >/dev/null 2>&1 || true
sed "s|__HOME__|${HOME}|" "${SBX}/platform/macos/launchagents/com.pi-sandbox-macos.herdr-bridge.plist" \
  > "${HOME}/Library/LaunchAgents/com.pi-sandbox-macos.herdr-bridge.plist"
launchctl bootstrap "gui/$(id -u)" \
  "${HOME}/Library/LaunchAgents/com.pi-sandbox-macos.herdr-bridge.plist" && echo "herdr-bridge: agent loaded"
