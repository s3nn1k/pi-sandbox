#!/usr/bin/env bash
set -uo pipefail
SBX="$HOME/pi-sandbox"
# shellcheck source=/dev/null
source "$SBX/launch/lib.sh" \
  || { echo "pi: нет $SBX/launch/lib.sh (неполный деплой?)" >&2; exit 1; }
if ! declare -F run_to >/dev/null 2>&1 || ! declare -p CACHE >/dev/null 2>&1; then
  echo "pi: повреждён $SBX/launch/lib.sh" >&2
  exit 1
fi

platform_deps || exit 1
engine_ready || exit 1
guard_checks || exit 1

docker image inspect pi-agent-base >/dev/null 2>&1 \
  || { echo "pi: нет образа pi-agent-base — make -C $SBX image" >&2; exit 1; }
DIND_ID="$(compose ps -q dind)"
live_sess="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-')"
if [ "$live_sess" -gt 0 ]; then
  dind_state="$(docker inspect -f '{{.State.Health.Status}}' "$DIND_ID" 2>/dev/null)"
  [ "$dind_state" = healthy ] || echo "pi: WARN: живые сессии при нездоровом dind — up пропущен (пересоздание осиротит их)" >&2
else
  dind_state="$(docker inspect -f '{{.State.Health.Status}}' "$DIND_ID" 2>/dev/null)"
  if [ "$dind_state" = unhealthy ]; then
    echo "pi: dind unhealthy — рестартую (живых сессий нет)" >&2
    compose restart dind >/dev/null 2>&1
  fi
  compose up -d --wait --wait-timeout 180 ${PLATFORM_UP_SERVICES[@]+"${PLATFORM_UP_SERVICES[@]}"} >/dev/null 2>&1 \
    || { echo "pi: ${PLATFORM_UP_SERVICES[*]} не поднялись (см. compose logs)" >&2; exit 1; }
  DIND_ID="$(compose ps -q dind)"
fi
[ -n "${DIND_ID:-}" ] || { echo "pi: dind-id не найден" >&2; exit 1; }
if ! bridge_pinned; then
  if [ "$live_sess" -gt 0 ]; then
    echo "pi: pinet со старым hash-bridge (pi-sbx0 нет), живые сессии есть — пересоздание сети осиротит их; останови pi и прогони install.sh" >&2
    exit 1
  fi
  echo "pi: pinet со старым hash-bridge (pi-sbx0 нет) — пересоздаю сеть проекта (живых сессий нет)" >&2
  if ! { compose down >&2 \
       && compose up -d --wait --wait-timeout 180 ${PLATFORM_UP_SERVICES[@]+"${PLATFORM_UP_SERVICES[@]}"} >/dev/null 2>&1; }; then
    echo "pi: пересоздание сети не удалось (см. compose logs)" >&2
    exit 1
  fi
  DIND_ID="$(compose ps -q dind)"
  bridge_pinned \
    || { echo "pi: pi-sbx0 не появился после пересоздания сети — проверь driver_opts com.docker.network.bridge.name в platform/$PI_SANDBOX_PLATFORM/compose.override.yaml" >&2; exit 1; }
fi
guard_probe || exit 1
echo "$DIND_ID"
