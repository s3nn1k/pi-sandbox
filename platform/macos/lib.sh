# shellcheck shell=bash
# shellcheck disable=SC2034
PLATFORM_DOTFILES_DIR="$HOME/dotfiles"
PLATFORM_UP_SERVICES=(dind herdr-bridge)

platform_deps() {
  local dep
  for dep in jq rsync nc yq; do
    command -v "$dep" >/dev/null 2>&1 || { echo "pi: нет зависимости $dep" >&2; return 1; }
  done
}

log_tail() { tail -n 5 "$1" 2>/dev/null | sed 's/^/  | /' >&2; }

engine_ready() {
  docker context inspect colima >/dev/null 2>&1 \
    || docker context create colima --docker "host=unix://$HOME/.colima/default/docker.sock" >/dev/null 2>&1
  docker context show | grep -qx colima || docker context use colima >/dev/null 2>&1
  docker info >/dev/null 2>&1 && return 0
  mkdir -p "$CACHE"
  run_to 180 colima start >"$CACHE/colima-start.log" 2>&1
  docker info >/dev/null 2>&1 && return 0
  if ! docker ps >/dev/null 2>&1; then
    echo "pi: демон мёртв полностью (wedged VM) — сессии недостижимы, один жёсткий цикл" >&2
  elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^pi-sess-'; then
    echo "pi: живые pi-sess-* — жёсткий цикл VM запрещён; останови сессии или ре-ран" >&2
    return 1
  fi
  run_to 60 colima stop --force >/dev/null 2>&1
  run_to 180 colima start >"$CACHE/colima-start.log" 2>&1
  docker info >/dev/null 2>&1 && return 0
  echo "pi: docker-VM недоступна после force-stop + colima start (лог: $CACHE/colima-start.log):" >&2
  log_tail "$CACHE/colima-start.log"
  return 1
}

vm_firewall_rules_present() {
  colima ssh -- sudo sh -c '
    iptables -C DOCKER-USER -d 192.168.5.2/32 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN \
    && iptables -C DOCKER-USER -d 192.168.5.2/32 -p tcp --dport 4761 -j RETURN \
    && iptables -C DOCKER-USER -d 192.168.5.2/32 -j DROP' >/dev/null 2>&1
}

guard_checks() { :; }

guard_probe() { :; }

date_to_epoch() { date -u -j -f '%Y-%m-%d %H:%M:%S' "$1" +%s 2>/dev/null; }

bridge_pinned() { :; }

bind_preflight() {
  local bind_srcs src found mnt
  [ -f "$HOME/.colima/default/colima.yaml" ] \
    || { echo "pi: нет $HOME/.colima/default/colima.yaml (colima не настроена?)" >&2; return 1; }
  bind_srcs="$(compose config --format json 2>/dev/null \
    | jq -r '[.services[].volumes[]? | select(.type == "bind") | .source] | unique[]' 2>/dev/null)"
  [ -n "$bind_srcs" ] || { echo "pi: pre-flight: не смог разобрать bind-источники compose" >&2; return 1; }
  while IFS= read -r src; do
    found=0
    while IFS= read -r mnt; do
      case "$src" in "$mnt"|"$mnt"/*) found=1; break ;; esac
    done < <(yq -r '.mounts[].location' "$HOME/.colima/default/colima.yaml" 2>/dev/null)
    [ "$found" = 1 ] || { echo "pi: bind-источник $src вне VM-маунтов — sandbox-sync + colima restart?" >&2; return 1; }
  done <<<"$bind_srcs"
}
