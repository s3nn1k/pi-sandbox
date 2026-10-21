#!/usr/bin/env bash
# Разворачивание песочницы на чистой машине (вызывается dotfiles/scripts/bootstrap.sh
# или руками). Идемпотентен.
set -euo pipefail
SBX="$(cd "$(dirname "$0")" && pwd)"

pf_anchor=pi-sandbox
sudo sed -i '' '/happ-local/d' /etc/pf.conf
sudo rm -f /etc/pf.anchors/happ-local
sudo cp "$SBX/pf/$pf_anchor" "/etc/pf.anchors/$pf_anchor"
if ! grep -q "$pf_anchor" /etc/pf.conf; then
  printf 'anchor "%s"\nload anchor "%s" from "/etc/pf.anchors/%s"\n' "$pf_anchor" "$pf_anchor" "$pf_anchor" \
    | sudo tee -a /etc/pf.conf >/dev/null
fi
sudo pfctl -f /etc/pf.conf || { echo "install: pf ruleset не загрузился" >&2; exit 1; }
sudo pfctl -E >/dev/null 2>&1 || { echo "install: pf enable failed" >&2; exit 1; }

chmod +x "$SBX/bin/"*

fresh_boot=0
if ! colima status >/dev/null 2>&1; then
  colima start --vm-type vz --mount-type virtiofs --cpu 4 --memory 10
  fresh_boot=1
fi
brew services start colima >/dev/null 2>&1 || true

while IFS= read -r root; do
  case "$root" in ""|"#"*) continue ;; esac
  mkdir -p "$HOME/${root%% *}"
done < "$SBX/pi-mounts"
cfg="$HOME/.colima/default/colima.yaml"
cfg_before="$(md5 -q "$cfg" 2>/dev/null || echo none)"
"$SBX/bin/sandbox-sync"
ln -sfn "$SBX/bin/sandbox-sync" "$HOME/.local/bin/sandbox-sync"
cfg_changed=0
[ "$(md5 -q "$cfg" 2>/dev/null || echo none)" != "$cfg_before" ] && cfg_changed=1

live_sess="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-' || true)"
if [ "$live_sess" -gt 0 ]; then
  echo "install: $live_sess живых агент-сессий — рестарт VM оборвёт их. Останови pi или ре-ран позже." >&2
  exit 1
fi
if [ "$cfg_changed" = 1 ]; then
  echo "install: colima.yaml изменился — применяю рестартом VM"
  colima restart >/dev/null
else
  echo "install: конфиг VM без изменений — рестарт не нужен"
fi
fw="$(colima ssh -- sudo iptables -S DOCKER-USER 2>/dev/null)"
echo "$fw" | grep -q 'ESTABLISHED,RELATED -j RETURN' \
  && echo "$fw" | grep -q -- '--dport 4761 -j RETURN' \
  && echo "$fw" | grep -q '192.168.5.2/32 -j DROP' \
  || { echo "install: firewall неполный (нет EST/4761/DROP или весь отсутствует)" >&2; exit 1; }

mkdir -p "$HOME/Library/Logs/pi-sandbox" "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
ln -sfn "$SBX/bin/herdr-sock-bridge" "$HOME/.local/bin/herdr-sock-bridge"
launchctl bootout "gui/$(id -u)/com.s3nn1k.herdr-bridge" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/com.pi-sandbox.herdr-bridge" >/dev/null 2>&1 || true
sed "s|__HOME__|$HOME|" "$SBX/launchagents/com.pi-sandbox.herdr-bridge.plist" \
  > "$HOME/Library/LaunchAgents/com.pi-sandbox.herdr-bridge.plist"
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.pi-sandbox.herdr-bridge.plist" && echo "herdr-bridge: agent loaded"

make -C "$SBX" image \
  || echo "install: WARN: make image не прошёл — догони вручную: make -C $SBX image" >&2
if [ "$live_sess" = 0 ] 2>/dev/null; then
  make -C "$SBX" seeds \
    || echo "install: WARN: seeds не прошли — повтори: make -C $SBX seeds" >&2
fi
