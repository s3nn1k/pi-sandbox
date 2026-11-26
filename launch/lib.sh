# shellcheck shell=bash
# shellcheck disable=SC2034
CACHE="$HOME/tmp/pi-cache"
SBX="$HOME/pi-sandbox"

PI_SANDBOX_PLATFORM="${PI_SANDBOX_PLATFORM:-$(uname -s)}"
case "$PI_SANDBOX_PLATFORM" in
  Linux|fedora) PI_SANDBOX_PLATFORM=fedora ;;
  Darwin|macos) PI_SANDBOX_PLATFORM=macos ;;
  *)
    echo "pi: неизвестная платформа '$PI_SANDBOX_PLATFORM' (ожидаются fedora/macos; uname: $(uname -s))" >&2
    exit 1
    ;;
esac

compose() {
  docker compose -f "$SBX/compose.yaml" -f "$SBX/platform/$PI_SANDBOX_PLATFORM/compose.override.yaml" "$@"
}

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

# shellcheck disable=SC1090
. "$SBX/platform/$PI_SANDBOX_PLATFORM/lib.sh" \
  || { echo "pi: нет $SBX/platform/$PI_SANDBOX_PLATFORM/lib.sh (неполный деплой?)" >&2; exit 1; }
declare -p PLATFORM_UP_SERVICES >/dev/null 2>&1 \
  || { echo "pi: platform lib должен определить PLATFORM_UP_SERVICES" >&2; exit 1; }
