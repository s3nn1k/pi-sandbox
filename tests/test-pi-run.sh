#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
pi_run="$repo_root/bin/pi-run"

mkdir -p "$HOME/tmp"
fixture_root="$(mktemp -d "$HOME/tmp/pi-run-test.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

fixture_home="$fixture_root/home"
stub_bin="$fixture_root/bin"
stub_log="$fixture_root/stub.log"
mkdir -p "$fixture_home/pi-sandbox" "$stub_bin" \
  "$fixture_home/projects/personal/app" "$fixture_home/dotfiles-fedora" "$fixture_home/tmp/scratch"
cp -a "$repo_root/launch" "$fixture_home/pi-sandbox/"
cp -a "$repo_root/platform" "$fixture_home/pi-sandbox/"

cat >"$fixture_home/pi-sandbox/pi-mounts" <<'EOF'

# comment
projects
.pi/agent/sessions vm-only
tmp vm-only
go/pkg/mod vm-only ro
EOF

write_session_fixture() {
  local fixture_file="$1" session_cwd="$2"
  printf '{"type":"session","cwd":"%s"}\n' "$session_cwd" >"$fixture_file"
}
write_session_fixture "$fixture_root/host-session.jsonl" "$fixture_home/dotfiles-fedora"
write_session_fixture "$fixture_root/sbx-session.jsonl" "$fixture_home/projects/personal/app"
printf 'not json at all\n' >"$fixture_root/garbage-session.jsonl"
: >"$stub_log"

cat >"$stub_bin/pi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PI_STUB_LOG"
exit 7
EOF
cat >"$stub_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$stub_bin/docker" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "info" ]] && exit 1
if [[ "${1:-}" == "ps" && -n "${DOCKER_PS_OUT:-}" ]]; then
  printf '%s\n' "$DOCKER_PS_OUT"
fi
exit 0
EOF
cat >"$stub_bin/colima" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$stub_bin/yq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$stub_bin/nc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$stub_bin/pi" "$stub_bin/systemctl" "$stub_bin/docker" "$stub_bin/colima" "$stub_bin/yq" "$stub_bin/nc"

case_index=0
failures=0

case_extra_env="PI_SANDBOX_PLATFORM=fedora"

run_case() {
  local spec="$1"
  shift
  local case_name case_cwd expected_rc expected_stderr expected_stub_args
  IFS='|' read -r case_name case_cwd expected_rc expected_stderr expected_stub_args <<<"$spec"
  local -a extra_env=()
  [[ -n "$case_extra_env" ]] && read -r -a extra_env <<<"$case_extra_env"
  case_extra_env="PI_SANDBOX_PLATFORM=fedora"

  : >"$stub_log"
  local stderr_file="$fixture_root/stderr.out" stdout_file="$fixture_root/stdout.out" mismatched=0
  (
    cd "$case_cwd" || exit 99
    exec env HOME="$fixture_home" PATH="$stub_bin:$PATH" PI_STUB_LOG="$stub_log" ${extra_env[@]+"${extra_env[@]}"} "$pi_run" "$@"
  ) >"$stdout_file" 2>"$stderr_file"
  local actual_rc=$?
  local actual_stub_args
  actual_stub_args="$(cat "$stub_log")"
  (( ++case_index ))

  if (( actual_rc != expected_rc )); then
    echo "FAIL $case_index $case_name: ожидалось rc=$expected_rc, факт rc=$actual_rc, stderr: $(cat "$stderr_file")"
    mismatched=1
  fi
  if [[ "$expected_stderr" == "EMPTY" ]]; then
    if [[ -s "$stderr_file" ]]; then
      echo "FAIL $case_index $case_name: ожидался пустой stderr, факт: $(cat "$stderr_file")"
      mismatched=1
    fi
  elif ! grep -Fq -- "$expected_stderr" "$stderr_file"; then
    echo "FAIL $case_index $case_name: в stderr нет '$expected_stderr', факт: $(cat "$stderr_file")"
    mismatched=1
  fi
  if [[ "$actual_stub_args" != "$expected_stub_args" ]]; then
    echo "FAIL $case_index $case_name: лог стаба ожидался '$expected_stub_args', факт '$actual_stub_args'"
    mismatched=1
  fi

  if (( mismatched == 0 )); then
    echo "ok $case_index $case_name"
  else
    (( ++failures ))
  fi
}

run_case "host_cwd_outside_roots|$fixture_home/dotfiles-fedora|7|вне корней песочницы — запускаю хостовым pi|--version" --version
run_case "vm_only_root_is_host|$fixture_home/tmp/scratch|7|вне корней песочницы — запускаю хостовым pi|--version" --version
run_case "root_exact_is_sandbox|$fixture_home/projects|1|docker недоступен||"
run_case "nested_root_is_sandbox|$fixture_home/projects/personal/app|1|docker недоступен||"
run_case "session_hostborn_from_sandbox_cwd|$fixture_home/projects/personal/app|7|сессия создана вне песочницы|--session $fixture_root/host-session.jsonl --version" --session "$fixture_root/host-session.jsonl" --version
run_case "session_eq_form_hostborn|$fixture_home/projects/personal/app|7|сессия создана вне песочницы|--session=$fixture_root/host-session.jsonl" --session="$fixture_root/host-session.jsonl"
run_case "session_sbxborn_from_sandbox_cwd|$fixture_home/projects/personal/app|1|docker недоступен||" --session "$fixture_root/sbx-session.jsonl"
run_case "session_hostborn_from_host_cwd|$fixture_home/dotfiles-fedora|7|сессия создана вне песочницы|--session $fixture_root/host-session.jsonl" --session "$fixture_root/host-session.jsonl"
run_case "session_garbage_falls_to_cwd|$fixture_home/dotfiles-fedora|7|вне корней песочницы — запускаю хостовым pi|--session $fixture_root/garbage-session.jsonl" --session "$fixture_root/garbage-session.jsonl"
run_case "session_missing_value_falls_to_cwd|$fixture_home/dotfiles-fedora|7|вне корней песочницы — запускаю хостовым pi|--session" --session
run_case "session_nonexistent_falls_to_cwd|$fixture_home/dotfiles-fedora|7|вне корней песочницы — запускаю хостовым pi|--session $fixture_root/nope.jsonl" --session "$fixture_root/nope.jsonl"
run_case "unsafe_bypasses_all|$fixture_home/dotfiles-fedora|7|EMPTY|--version" --unsafe --version

case_extra_env="PI_SANDBOX_PLATFORM=macos"
run_case "macos_vm_unreachable|$fixture_home/projects/personal/app|1|docker-VM недоступна||"
case_extra_env="PI_SANDBOX_PLATFORM=macos DOCKER_PS_OUT=pi-sess-999"
run_case "macos_wedge_cycle_forbidden|$fixture_home/projects/personal/app|1|жёсткий цикл VM запрещён||"
case_extra_env="PI_SANDBOX_PLATFORM=solaris"
run_case "platform_unknown_fails_loud|$fixture_home/projects/personal/app|1|неизвестная платформа||"

mkdir -p "$fixture_home/.pi/agent/install"
printf '9.9.9\n' >"$fixture_home/.pi/agent/install/current-version"
fixture_cache="$fixture_home/tmp/pi-cache"

sync_lock_none() { :; }
sync_lock_old() {
  mkdir "$fixture_cache/.sync-lock"
  touch -d '3 minutes ago' "$fixture_cache/.sync-lock"
}
sync_lock_fresh() { mkdir "$fixture_cache/.sync-lock"; }
sync_lock_live() {
  mkdir "$fixture_cache/.sync-lock"
  sleep 3 &
  printf '%s\n' "$!" >"$fixture_cache/.sync-lock/pid"
}

run_sync_case() {
  local case_name="$1" timeout_s="$2" setup="$3"
  rm -rf "$fixture_cache/.sync-lock"
  "$setup"
  local rc
  env HOME="$fixture_home" PATH="$stub_bin:$PATH" timeout "$timeout_s" \
    "$fixture_home/pi-sandbox/launch/steps/sync.sh" >"$fixture_root/sync.out" 2>"$fixture_root/sync.err"
  rc=$?
  (( ++case_index ))
  local mismatched=0
  if (( rc != 1 )); then
    echo "FAIL $case_index $case_name: ожидался rc=1 (sync падает на pi-рантайм), факт rc=$rc, stderr: $(cat "$fixture_root/sync.err")"
    mismatched=1
  fi
  if ! grep -Fq 'pi-рантайм не найден' "$fixture_root/sync.err"; then
    echo "FAIL $case_index $case_name: в stderr нет 'pi-рантайм не найден', факт: $(cat "$fixture_root/sync.err")"
    mismatched=1
  fi
  if [ -d "$fixture_cache/.sync-lock" ]; then
    echo "FAIL $case_index $case_name: sync-lock не снят после отказа"
    mismatched=1
  fi
  if (( mismatched == 0 )); then
    echo "ok $case_index $case_name"
  else
    (( ++failures ))
  fi
}

run_sync_case "sync_lock_acquire_and_release" 10 sync_lock_none
run_sync_case "sync_lock_stale_no_pid_removed" 10 sync_lock_old
run_sync_case "sync_lock_fresh_no_pid_recovers_fast" 25 sync_lock_fresh
run_sync_case "sync_lock_live_pid_waited_out" 15 sync_lock_live

: >"$fixture_home/pi-sandbox/launch/lib.sh"
run_case "empty_lib_guard_fails|$fixture_home/projects/personal/app|1|повреждён||"

echo "итог: $((case_index - failures))/$case_index кейсов ok, $failures FAIL"
(( failures == 0 )) || exit 1
