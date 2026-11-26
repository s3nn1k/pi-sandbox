#!/usr/bin/env bash
set -uo pipefail
SBX="$HOME/pi-sandbox"
source "$SBX/launch/lib.sh" \
  || { echo "pi: нет $SBX/launch/lib.sh (неполный деплой?)" >&2; exit 1; }

mkdir -p "$CACHE"
sync_lock="$CACHE/.sync-lock"
lock_tries=0
until mkdir "$sync_lock" 2>/dev/null; do
  (( ++lock_tries > 300 )) && { echo "pi: sync-lock занят (pid ${lock_pid:-?})" >&2; exit 1; }
  lock_pid="$(cat "$sync_lock/pid" 2>/dev/null)"
  if [ -z "$lock_pid" ] && [ -z "$(find "$sync_lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    sleep 1
    continue
  fi
  if { [ -z "$lock_pid" ] || ! kill -0 "$lock_pid" 2>/dev/null; } \
     && ! pgrep -f 'pi-cache/(brain|nvim|dotfiles)' >/dev/null 2>&1; then
    rm -rf "$sync_lock"
    continue
  fi
  sleep 1
done
echo $$ > "$sync_lock/pid"
sync_lock_release() { [ "$(cat "$sync_lock/pid" 2>/dev/null)" = "$$" ] && rm -rf "$sync_lock"; }

pi_ver="$(cat "$HOME/.pi/agent/install/current-version" 2>/dev/null)"
PI_SRC="$HOME/.pi/agent/install/releases/$pi_ver/node_modules/@earendil-works/pi-coding-agent"
[ -f "$PI_SRC/dist/bundle/cli.js" ] \
  || { echo "pi: pi-рантайм не найден ($PI_SRC/dist/bundle/cli.js; current-version: ${pi_ver:-пусто}) — проверь ~/.pi/agent/install" >&2
       sync_lock_release
       exit 1; }

mkdir -p "$CACHE/brain" "$CACHE/nvim" "$CACHE/dotfiles"
rsync -a --copy-unsafe-links --delete --exclude /sessions --exclude /missions "$HOME/.pi/agent/" "$CACHE/brain/" &
rs_brain=$!
rsync -a --delete "$HOME/.config/nvim/" "$CACHE/nvim/" &
rs_nvim=$!
rsync -a --delete --exclude .git "$HOME/dotfiles-fedora/" "$CACHE/dotfiles/" &
rs_dot=$!
trap 'kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release' INT TERM HUP
{ sed -e 's#~/\.config/git/credentials\.gitconfig#~/credentials/git/gitconfig#' \
       "$HOME/dotfiles-fedora/gitconfig"; printf '\n[safe]\n\tdirectory = *\n'; } > "$CACHE/.gitconfig.tmp" \
  || { echo "pi: нет ~/dotfiles-fedora/gitconfig" >&2; rm -f "$CACHE/.gitconfig.tmp"; kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release; exit 1; }
if [ -d "$CACHE/gitconfig" ]; then
  rm -rf "$CACHE/gitconfig"
fi
mv -f "$CACHE/.gitconfig.tmp" "$CACHE/gitconfig" \
  || { echo "pi: не смог атомарно поставить $CACHE/gitconfig" >&2; rm -f "$CACHE/.gitconfig.tmp"; kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release; exit 1; }
[ -d "$HOME/credentials/git" ] \
  || { echo "pi: нет ~/credentials/git (bootstrap/unlock не выполнен?)" >&2; kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release; exit 1; }
[ -d "$CACHE/credentials" ] && find "$CACHE/credentials" -mindepth 1 -delete
mkdir -p "$CACHE/credentials/git"
for f in "$HOME/credentials/git/gitconfig" "$HOME/credentials/git/"*.gitconfig; do
  [ -f "$f" ] || continue
  cp "$f" "$CACHE/credentials/git/$(basename "$f")" \
    || { echo "pi: сбой копирования $f" >&2; kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release; exit 1; }
done
[ -d "$CACHE/git-credentials" ] && rm -rf "$CACHE/git-credentials"
install -m 600 "$HOME/credentials/agents-credentials/git-credentials" "$CACHE/git-credentials" \
  || { echo "pi: нет $HOME/credentials/agents-credentials/git-credentials" >&2; kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release; exit 1; }
mkdir -p "$CACHE/agent-creds"
for cred_name in kubeconfig pgpass pg_service.conf; do
  cred_src="$HOME/credentials/agents-credentials/$cred_name"
  cred_dst="$CACHE/agent-creds/$cred_name"
  if [ -s "$cred_src" ]; then
    if ! { install -m 600 "$cred_src" "$CACHE/agent-creds/.$cred_name.tmp" \
         && mv -f "$CACHE/agent-creds/.$cred_name.tmp" "$cred_dst"; }; then
      rm -f "$CACHE/agent-creds/.$cred_name.tmp"
      echo "pi: сбой копирования $cred_src" >&2
      kill $rs_brain $rs_nvim $rs_dot 2>/dev/null
      wait
      sync_lock_release
      exit 1
    fi
  else
    rm -f "$cred_dst" 2>/dev/null \
      || { echo "pi: не смог удалить устаревший $cred_dst" >&2; kill $rs_brain $rs_nvim $rs_dot 2>/dev/null; wait; sync_lock_release; exit 1; }
  fi
done
sync_fail=0
wait $rs_brain || sync_fail=1
wait $rs_nvim || sync_fail=1
wait $rs_dot || sync_fail=1
mkdir -p "$CACHE/dotfiles/bin" \
  && install -m 755 "$SBX/bin/pi" "$CACHE/dotfiles/bin/pi" \
  || sync_fail=1
mkdir -p "$CACHE/brain/skills" && cp -a "$SBX/skills/sandbox-environment" "$CACHE/brain/skills/" || sync_fail=1
trap - INT TERM HUP
sync_lock_release
if (( sync_fail )); then
  echo "pi: сбой синхронизации кэша — отмена запуска" >&2
  exit 1
fi
