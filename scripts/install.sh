#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/launch/lib.sh" \
  || { echo "install: нет launch/lib.sh рядом со scripts/install.sh" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
  echo "install: запуск под root запрещён — sudo вызывается внутри шагов там, где нужно" >&2
  exit 1
fi

live_sess="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-' || true)"
if [ "${live_sess:-0}" -gt 0 ]; then
  echo "install: ${live_sess:-0} живых агент-сессий — останови pi или ре-ран позже" >&2
  exit 1
fi

while IFS= read -r root; do
  case "${root}" in ""|"#"*) continue ;; esac
  mkdir -p "${HOME}/${root%% *}"
done < "${SBX}/pi-mounts"

chmod +x "${SBX}"/platform/*/install/*.sh \
  "${SBX}"/platform/macos/sandbox-sync "${SBX}"/platform/fedora/herdr-sock-bridge \
  "${SBX}"/platform/macos/herdr-sock-bridge "${SBX}"/bin/* "${SBX}"/launch/steps/*.sh

case "${PI_SANDBOX_PLATFORM}" in
  fedora)
    "${SBX}/platform/fedora/install/deps.sh"
    "${SBX}/platform/fedora/install/polkit.sh"
    "${SBX}/platform/fedora/install/firewalld.sh"
    "${SBX}/platform/fedora/install/guard.sh"
    "${SBX}/platform/fedora/install/docker.sh"
    "${SBX}/platform/fedora/install/herdr-bridge.sh"
    "${SBX}/platform/fedora/install/image.sh"
    ;;
  macos)
    "${SBX}/platform/macos/install/pf.sh"
    "${SBX}/platform/macos/install/colima.sh"
    "${SBX}/platform/macos/install/herdr-bridge.sh"
    "${SBX}/platform/macos/install/image.sh"
    ;;
esac
