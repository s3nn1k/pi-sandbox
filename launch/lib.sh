# shellcheck shell=bash
# shellcheck disable=SC2034
CACHE="$HOME/tmp/pi-cache"

run_to() {
  local timeout_s="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$timeout_s"; kill -TERM "$pid" 2>/dev/null; sleep 5; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid"; local rc=$?
  kill -TERM "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

bridge_pinned() { ip -o link show pi-sbx0 >/dev/null 2>&1; }
