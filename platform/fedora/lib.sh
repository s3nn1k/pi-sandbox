# shellcheck shell=bash
# shellcheck disable=SC2034
PLATFORM_DOTFILES_DIR="$HOME/dotfiles-fedora"
PLATFORM_UP_SERVICES=(dind)

platform_deps() {
  local dep
  for dep in ip jq python3 rsync; do
    command -v "$dep" >/dev/null 2>&1 || { echo "pi: нет зависимости $dep" >&2; return 1; }
  done
}

engine_ready() {
  systemctl is-active docker >/dev/null 2>&1 \
    || { echo "pi: docker неактивен — sudo systemctl start docker" >&2; return 1; }
  docker info >/dev/null 2>&1 \
    || { echo "pi: docker недоступен (группа docker / re-login?)" >&2; return 1; }
}

date_to_epoch() { date -u -d "$1" +%s 2>/dev/null; }

guard_checks() {
  if ! systemctl is-active --quiet firewalld \
     || ! firewall-cmd --zone=docker --list-all 2>/dev/null | grep -qE '^[[:space:]]*target: %%REJECT%%[[:space:]]*$'; then
    echo "pi: S2 неактивен (зона docker не REJECT / firewalld стоит) — прогони install.sh" >&2
    return 1
  fi
  [ -f /run/pi-sandbox-guard.active ] \
    || { echo "pi: nft-guard не активен (systemctl status pi-sandbox-guard; прогони install.sh)" >&2; return 1; }
}

guard_probe() {
  [ "$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^pi-sess-')" -gt 0 ] && return 0

  local probe_out probe_pid probe_port
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
    return 1
  fi
  python3 -c 'import socket, sys
socket.create_connection(("172.28.0.1", int(sys.argv[1])), timeout=2).close()' "$probe_port" \
    || { echo "pi: проба guard: 172.28.0.1:$probe_port не отвечает с хоста" >&2; probe_cleanup; return 1; }
  if run_to 15 docker run --rm --network pi-agent_pinet --entrypoint node pi-agent-base \
    -e 'const net=require("net");const s=net.connect({host:"172.28.0.1",port:process.argv[1]},()=>{s.destroy();process.exit(0)});s.on("error",()=>process.exit(1));setTimeout(()=>{s.destroy();process.exit(1)},4000).unref();' \
    "$probe_port" >/dev/null; then
    echo "pi: nft-guard не держит трафик (проба из pinet прошла насквозь) — systemctl restart pi-sandbox-guard / прогони install.sh" >&2
    probe_cleanup
    return 1
  fi
  probe_cleanup
}

bind_preflight() {
  local bind_srcs src
  mkdir -p "$CACHE/herdr-bridge"
  bind_srcs="$(compose config --format json 2>/dev/null \
    | jq -r '[.services[].volumes[]? | select(.type == "bind") | .source] | unique[]' 2>/dev/null)"
  [ -n "$bind_srcs" ] || { echo "pi: pre-flight: не смог разобрать bind-источники compose" >&2; return 1; }
  while IFS= read -r src; do
    [ -e "$src" ] && continue
    case "$src" in
      */gitconfig|*/git-credentials) echo "pi: sync не создал $src" >&2; return 1 ;;
      *) mkdir -p "$src" ;;
    esac
  done <<<"$bind_srcs"
}

bridge_pinned() { ip -o link show pi-sbx0 >/dev/null 2>&1; }
