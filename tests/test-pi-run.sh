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
mkdir -p "$fixture_home/pi-sandbox-fedora" "$stub_bin" \
  "$fixture_home/projects/personal/app" "$fixture_home/dotfiles-fedora" "$fixture_home/tmp/scratch"
cp -a "$repo_root/launch" "$fixture_home/pi-sandbox-fedora/"

cat >"$fixture_home/pi-sandbox-fedora/pi-mounts" <<'EOF'

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
exit 0
EOF
chmod +x "$stub_bin/pi" "$stub_bin/systemctl" "$stub_bin/docker"

case_index=0
failures=0

run_case() {
  local spec="$1"
  shift
  local case_name case_cwd expected_rc expected_stderr expected_stub_args
  IFS='|' read -r case_name case_cwd expected_rc expected_stderr expected_stub_args <<<"$spec"

  : >"$stub_log"
  local stderr_file="$fixture_root/stderr.out" stdout_file="$fixture_root/stdout.out" mismatched=0
  (
    cd "$case_cwd" || exit 99
    exec env HOME="$fixture_home" PATH="$stub_bin:$PATH" PI_STUB_LOG="$stub_log" "$pi_run" "$@"
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

echo "итог: $((case_index - failures))/$case_index кейсов ok, $failures FAIL"
(( failures == 0 )) || exit 1
