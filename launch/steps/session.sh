#!/usr/bin/env bash
set -uo pipefail
SBX="$HOME/pi-sandbox"
source "$SBX/launch/lib.sh" \
  || { echo "pi: нет $SBX/launch/lib.sh (неполный деплой?)" >&2; exit 1; }

hpane="$(run_to 5 herdr pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty')"
: "${hpane:=${HERDR_PANE_ID:-}}"

orphan_ttl=21600
while IFS= read -r c; do
  pgrep -f -- "${c}([^0-9]|$)" >/dev/null 2>&1 && continue
  s=$(docker inspect -f '{{.State.StartedAt}}' "$c" 2>/dev/null) || continue
  s=${s%%.*}; s=${s/T/ }
  age=$(( $(date +%s) - $(date -u -d "$s" +%s 2>/dev/null || echo 99999999999) ))
  (( age > orphan_ttl )) && docker rm -f "$c" >/dev/null 2>&1
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep '^pi-sess-')
if [ -n "$(find "$CACHE/.dind-prune-stamp" -mtime +1 2>/dev/null)" ] || [ ! -f "$CACHE/.dind-prune-stamp" ]; then
  inner_ttl=$(( 24 * 3600 ))
  now=$(date +%s)
  mapfile -t inner_containers < <(docker exec "$DIND_ID" docker ps -q 2>/dev/null)
  while IFS= read -r line; do
    cont_id="${line%% *}"; started="${line#* }"
    started="${started%%.*}"; started="${started/T/ }"
    started_at=$(date -u -d "$started" +%s 2>/dev/null) || continue
    (( now - started_at > inner_ttl )) && docker exec "$DIND_ID" docker stop "$cont_id" >/dev/null 2>&1
  done < <(docker exec "$DIND_ID" docker inspect -f '{{.Id}} {{.State.StartedAt}}' \
    "${inner_containers[@]}" 2>/dev/null)
  prune_log="$CACHE/.dind-prune-last.log"
  if [ -n "$DIND_ID" ] && run_to 120 docker exec "$DIND_ID" docker system prune -f --filter until=48h >"$prune_log" 2>&1; then
    touch "$CACHE/.dind-prune-stamp"
    rm -f "$prune_log"
  else
    prune_rc=$?
    echo "pi: WARN: prune dind не удался (rc=$prune_rc; 143=таймаут 120с; лог: $prune_log)" >&2
    tail -n 5 "$prune_log" 2>/dev/null | sed 's/^/  | /' >&2
  fi
fi

nm="pi-sess-$$"
nm_state="$(docker inspect -f '{{.State.Status}}' "$nm" 2>/dev/null)"
if [ -n "$nm_state" ] && [ "$nm_state" != running ]; then
  docker rm -f "$nm" >/dev/null 2>&1
  echo "pi: убран stale-контейнер $nm (state=$nm_state)" >&2
fi
mkdir -p "$CACHE/herdr-bridge"
bind_srcs="$(docker compose -f "$SBX/compose.yaml" config --format json 2>/dev/null \
  | jq -r '[.services[].volumes[]? | select(.type == "bind") | .source] | unique[]' 2>/dev/null)"
[ -n "$bind_srcs" ] || { echo "pi: pre-flight: не смог разобрать bind-источники compose" >&2; exit 1; }
while IFS= read -r src; do
  [ -e "$src" ] && continue
  case "$src" in
    */gitconfig|*/git-credentials) echo "pi: sync не создал $src" >&2; exit 1 ;;
    *) mkdir -p "$src" ;;
  esac
done <<<"$bind_srcs"
HERDR_PANE_ID="$hpane" HERDR_AGENT=pi docker compose -f "$SBX/compose.yaml" run --rm --no-deps --name "$nm" pi-agent "$@"
rc=$?
reattach_tries=0
while [ $rc -ne 0 ]; do
  docker ps -a --format '{{.Names}}' | grep -q "^$nm$" || break
  (( ++reattach_tries > 10 )) && { echo "pi: reattach-кап 10 попыток — сессия нестабильна (docker logs $nm)" >&2; rc=1; break; }
  sess_state="$(docker inspect -f '{{.State.Status}}' "$nm" 2>/dev/null)"
  if [ "$sess_state" != running ]; then
    echo "pi: контейнер сессии не running (state=${sess_state:-?}) — reattach прекращён" >&2
    rc=1; break
  fi
  echo "pi: связь с контейнером оборвалась — переподключаюсь к живой сессии ($reattach_tries/10)" >&2
  docker compose -f "$SBX/compose.yaml" up -d --wait --wait-timeout 180 dind >/dev/null 2>&1 \
    || { echo "pi: dind не ожил — reattach отменён" >&2; rc=1; break; }
  bridge_pinned \
    || { echo "pi: pi-sbx0 пропал при reattach-up — сеть пересоздана без pinned bridge; перезапусти pi" >&2; rc=1; break; }
  sess_net="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$nm" 2>/dev/null)"
  if [ "$sess_net" != "container:$DIND_ID" ]; then
    echo "pi: сессия осиротела (dind пересоздан: $sess_net ≠ container:$DIND_ID) — нужен перезапуск pi" >&2
    rc=1; break
  fi
  sleep "$reattach_tries"
  docker start -a "$nm"
  rc=$?
done
exit "$rc"
