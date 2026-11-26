#!/usr/bin/env bash
set -uo pipefail
SBX="$HOME/pi-sandbox-fedora"
source "$SBX/launch/lib.sh" \
  || { echo "pi: нет $SBX/launch/lib.sh (неполный деплой?)" >&2; exit 1; }

for dep in ip jq python3 rsync; do
  command -v "$dep" >/dev/null 2>&1 || { echo "pi: нет зависимости $dep" >&2; exit 1; }
done

systemctl is-active docker >/dev/null 2>&1 \
  || { echo "pi: docker неактивен — sudo systemctl start docker" >&2; exit 1; }
docker info >/dev/null 2>&1 \
  || { echo "pi: docker недоступен (группа docker / re-login?)" >&2; exit 1; }
if ! systemctl is-active --quiet firewalld \
   || ! firewall-cmd --zone=docker --list-all 2>/dev/null | grep -qE '^[[:space:]]*target: %%REJECT%%[[:space:]]*$'; then
  echo "pi: S2 неактивен (зона docker не REJECT / firewalld стоит) — прогони install.sh" >&2
  exit 1
fi
[ -f /run/pi-sandbox-guard.active ] \
  || { echo "pi: nft-guard не активен (systemctl status pi-sandbox-guard; прогони install.sh)" >&2; exit 1; }

docker image inspect pi-agent-base >/dev/null 2>&1 \
  || { echo "pi: нет образа pi-agent-base — make -C $SBX image" >&2; exit 1; }
DIND_ID="$(docker compose -f "$SBX/compose.yaml" ps -q dind)"
live_sess="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-')"
if [ "$live_sess" -gt 0 ]; then
  dind_state="$(docker inspect -f '{{.State.Health.Status}}' "$DIND_ID" 2>/dev/null)"
  [ "$dind_state" = healthy ] || echo "pi: WARN: живые сессии при нездоровом dind — up пропущен (пересоздание осиротит их)" >&2
else
  dind_state="$(docker inspect -f '{{.State.Health.Status}}' "$DIND_ID" 2>/dev/null)"
  if [ "$dind_state" = unhealthy ]; then
    echo "pi: dind unhealthy — рестартую (живых сессий нет)" >&2
    docker compose -f "$SBX/compose.yaml" restart dind >/dev/null 2>&1
  fi
  docker compose -f "$SBX/compose.yaml" up -d --wait --wait-timeout 180 dind >/dev/null 2>&1 \
    || { echo "pi: dind не поднялся (см. docker compose -f $SBX/compose.yaml logs)" >&2; exit 1; }
  DIND_ID="$(docker compose -f "$SBX/compose.yaml" ps -q dind)"
fi
[ -n "${DIND_ID:-}" ] || { echo "pi: dind-id не найден" >&2; exit 1; }
if ! bridge_pinned; then
  if [ "$live_sess" -gt 0 ]; then
    echo "pi: pinet со старым hash-bridge (pi-sbx0 нет), живые сессии есть — пересоздание сети осиротит их; останови pi и прогони install.sh" >&2
    exit 1
  fi
  echo "pi: pinet со старым hash-bridge (pi-sbx0 нет) — пересоздаю сеть проекта (живых сессий нет)" >&2
  if ! { docker compose -f "$SBX/compose.yaml" down >&2 \
       && docker compose -f "$SBX/compose.yaml" up -d --wait --wait-timeout 180 dind >/dev/null 2>&1; }; then
    echo "pi: пересоздание сети не удалось (см. docker compose -f $SBX/compose.yaml logs)" >&2
    exit 1
  fi
  DIND_ID="$(docker compose -f "$SBX/compose.yaml" ps -q dind)"
  bridge_pinned \
    || { echo "pi: pi-sbx0 не появился после пересоздания сети — проверь driver_opts com.docker.network.bridge.name в compose.yaml" >&2; exit 1; }
fi
if [ "$live_sess" -eq 0 ]; then
  probe_out="$(mktemp)"
  python3 -c '
import socket
import time

listener = socket.socket()
listener.bind(("172.28.0.1", 0))
listener.listen(1)
print(listener.getsockname()[1], flush=True)
while True:
    time.sleep(3600)
' >"$probe_out" &
  probe_pid=$!
  probe_cleanup() {
    kill "$probe_pid" 2>/dev/null
    wait "$probe_pid" 2>/dev/null
    rm -f "$probe_out"
  }
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    probe_port="$(head -n 1 "$probe_out")"
    [ -n "$probe_port" ] && break
    sleep 0.5
  done
  if [ -z "$probe_port" ] || ! kill -0 "$probe_pid" 2>/dev/null; then
    echo "pi: проба guard: слушатель на 172.28.0.1 не поднялся" >&2
    probe_cleanup
    exit 1
  fi
  python3 -c 'import socket, sys
socket.create_connection(("172.28.0.1", int(sys.argv[1])), timeout=2).close()' "$probe_port" \
    || { echo "pi: проба guard: 172.28.0.1:$probe_port не отвечает с хоста" >&2; probe_cleanup; exit 1; }
  if run_to 15 docker run --rm --network pi-agent_pinet --entrypoint node pi-agent-base \
    -e 'const net=require("net");const s=net.connect({host:"172.28.0.1",port:process.argv[1]},()=>{s.destroy();process.exit(0)});s.on("error",()=>process.exit(1));setTimeout(()=>{s.destroy();process.exit(1)},4000).unref();' \
    "$probe_port" >/dev/null; then
    echo "pi: nft-guard не держит трафик (проба из pinet прошла насквозь) — systemctl restart pi-sandbox-guard / прогони install.sh" >&2
    probe_cleanup
    exit 1
  fi
  probe_cleanup
fi
echo "$DIND_ID"
