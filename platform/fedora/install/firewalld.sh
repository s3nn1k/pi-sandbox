#!/usr/bin/env bash
set -euo pipefail

if ! systemctl is-active --quiet firewalld; then
  echo "install: firewalld неактивен — sudo systemctl start firewalld" >&2
  exit 1
fi
if ! firewall-cmd --permanent --get-zones 2>/dev/null | grep -qw docker; then
  sudo firewall-cmd --permanent --new-zone=docker
  sudo firewall-cmd --permanent --zone=docker --set-target='%%REJECT%%'
  sudo firewall-cmd --reload
elif ! firewall-cmd --get-zones 2>/dev/null | grep -qw docker; then
  sudo firewall-cmd --reload
fi
if ! firewall-cmd --info-zone docker 2>/dev/null | grep -qE '^[[:space:]]*target: %%REJECT%%[[:space:]]*$'; then
  sudo firewall-cmd --permanent --zone=docker --set-target='%%REJECT%%'
  sudo firewall-cmd --reload
fi
firewall-cmd --info-zone docker 2>/dev/null | grep -qE '^[[:space:]]*target: %%REJECT%%[[:space:]]*$' \
  || { echo "install: target зоны docker не применился после reload" >&2; exit 1; }
