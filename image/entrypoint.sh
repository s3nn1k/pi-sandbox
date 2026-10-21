#!/bin/sh
# Экспорт агентских токенов из ~/.git-credentials (формат git-credential-store,
# смонтирован из ~/credentials/agents-credentials) в env для glab/gh.
# Git кормится credential.helper=store из хостового gitconfig сам — тут только env.
# Ограничение парсера: токены без '@' (glpat-*/github_pat_* — ок).
if [ ! -s /run/secrets/pi-git-credentials ]; then
  echo "entrypoint: /run/secrets/pi-git-credentials пуст или отсутствует" >&2
  exit 1
fi
install -m 600 /run/secrets/pi-git-credentials "$HOME/.git-credentials" \
  || { echo "entrypoint: не смог установить git-credentials" >&2; exit 1; }
f="$HOME/.git-credentials"
if [ -s "$f" ]; then
  while IFS= read -r line; do
    case "$line" in
      https://*github.com*) t=${line#https://*:}; t=${t%%@*} ;;
      https://*gitlab*) t=${line#https://*:}; t=${t%%@*} ;;
      *) continue ;;
    esac
    [ -n "$t" ] || continue
    case "$line" in
      https://*github.com*) GH_TOKEN="$t"; export GH_TOKEN ;;
      https://*gitlab*)
        GITLAB_HOST="${line#https://}"; GITLAB_HOST="${GITLAB_HOST%%/*}"
        GITLAB_TOKEN="$t"; export GITLAB_HOST GITLAB_TOKEN ;;
    esac
  done < "$f"
fi
exec pi "$@"
