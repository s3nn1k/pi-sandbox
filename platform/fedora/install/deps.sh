#!/usr/bin/env bash
set -euo pipefail

dep_pkg() {
  case "${1}" in
    firewall-cmd) echo firewalld ;;
    nft) echo nftables ;;
    docker) echo docker-ce ;;
    *) echo "${1}" ;;
  esac
}
for dep in git make curl jq rsync python3 systemctl firewall-cmd nft docker; do
  command -v "${dep}" >/dev/null 2>&1 \
    || { echo "install: нет зависимости ${dep} — sudo dnf install $(dep_pkg "${dep}")" >&2; exit 1; }
done

